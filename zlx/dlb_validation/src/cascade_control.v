`timescale 1ns / 1ps
// Two independent 8-clock PID cores. All logic uses clk; ms_tick is only an enable.
// Coincident deadlines: snapshot both inputs, B completes first, then A uses NEW B result.
// Auto-return (auto_retry only): PURE PID, exactly like changing goal_B. The measured
// position_count is mapped onto the ring-equivalent point nearest to goal_position by a
// continuously-running normalizer (shortest path), then the original kp_b/ki_b/kd_b and
// output limit drive the cart to the goal - no gain switch, no Ki gate, no brake cap.
// Frozen capture point: hold_pos latches position_count at capture; during the wait-for-
// center-stable phase and the 2s settle delay the PID brakes the cart back to hold_pos.
module cascade_control #(
    parameter integer CASCADE_SIGN=-1, parameter integer ANGLE_OUTPUT_SIGN=1,
    parameter integer REV_COUNTS=1040, parameter integer ARRIVED=100,
    parameter integer JUMP_THRESH=500
)(input wire clk,rst_n,ms_tick,enable,capture_clear,auto_retry,demo_start,dual_loop,
    input wire [15:0] period_a_ms,period_b_ms,outer_limit_adc,outer_i_adc,
    input wire [7:0] inner_limit_percent,inner_i_percent,
    input wire signed [31:0] center_adc,goal_position,position_count,
    input wire [11:0] angle_adc,
    input wire signed [31:0] kp_a,ki_a,kd_a,kp_b,ki_b,kd_b,
    input wire [31:0] epoch_a,epoch_b,
    output wire signed [31:0] pid_pwm_ticks,
    output reg signed [31:0] a_goal,a_real,a_set_ticks,b_goal,b_real,b_set_adc,
    output wire returning,
    output reg demo_active_out,   // travel-in-progress flag (drives a LED)
    output wire a_done,b_done,
    output reg a_sample_valid, output wire [11:0] a_sample_adc);
    localparam IDLE=0,B_TICK=1,B_WAIT=2,A_TICK=3,A_WAIT=4,A_PREP=5;
    localparam integer HALF_REV=REV_COUNTS/2;
    // ---- continuous ring normalizer ----
    // norm_acc = (goal - position) folded into [-HALF_REV, HALF_REV]; mapped_pos is the
    // ring-equivalent point of position_count nearest to goal (shortest path).
    reg [4:0] norm_cnt;
    reg signed [33:0] norm_acc;
    reg signed [31:0] mapped_pos;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin norm_cnt<=0; norm_acc<=0; mapped_pos<=0; end
        else begin
            if(norm_cnt==0) begin
                norm_cnt<=5'd22;
                norm_acc<={goal_position[31],goal_position}-{position_count[31],position_count};
            end else begin
                norm_cnt<=norm_cnt-1'b1;
                if(norm_acc>HALF_REV) norm_acc<=norm_acc-REV_COUNTS;
                else if(norm_acc< -HALF_REV) norm_acc<=norm_acc+REV_COUNTS;
                else begin
                    mapped_pos<=goal_position-norm_acc[31:0];
                    norm_cnt<=0;
                end
            end
        end
    end
    wire signed [32:0] mapped_err={goal_position[31],goal_position}-{mapped_pos[31],mapped_pos};
    // Independent center-stable detection: angle within center_adc +/-200 for 10
    // consecutive 100ms windows (1 second), running from auto_retry=1 across swing-up and
    // balance, fully parallel with the capture logic. Once detected the result is LATCHED
    // and detection stops; then the 2s settle delay runs, then the return.
    localparam integer CENTER_BAND=200;
    reg [6:0] center_win_cnt;
    reg [3:0] center_cnt;
    reg center_latched;
    wire signed [12:0] center_err=$signed({1'b0,angle_adc})-$signed({1'b0,center_adc[11:0]});
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin center_win_cnt<=0; center_cnt<=0; center_latched<=0; end
        else if(!auto_retry) begin center_win_cnt<=0; center_cnt<=0; center_latched<=0; end
        else if(ms_tick&&!center_latched) begin
            if(center_win_cnt==99) begin
                center_win_cnt<=0;
                if((center_err<=CENTER_BAND)&&(center_err>=-CENTER_BAND)) begin
                    if(center_cnt==9) begin center_cnt<=10; center_latched<=1; end
                    else center_cnt<=center_cnt+1'b1;
                end else center_cnt<=0;
            end else center_win_cnt<=center_win_cnt+1'b1;
        end
    end
    wire center_stable=center_latched;
    // ---- independent position-stability detection (parallel with the center-stable
    // detection, no ordering between them). 100ms samples of position_count in a 10-slot
    // ring; once full (1 second), every fresh sample checks |now - 1s ago| <= POS_BAND(70).
    // The first passing 1-second window latches pos_stable. BOTH center_stable and
    // pos_stable are required before the settle delay starts.
    localparam integer POS_BAND=70;
    reg [6:0] pos_win_cnt;
    reg [3:0] pos_smp_cnt;
    // 10-deep shift chain instead of a dynamic-index array: no mux, saves LUTs
    reg signed [31:0] ps0,ps1,ps2,ps3,ps4,ps5,ps6,ps7,ps8,ps9;
    reg pos_stable;
    reg pos_eval;                       // one-cycle pipeline stage for the stability check
    reg signed [32:0] pos_delta_r;      // registered 1s differential
    wire signed [32:0] pos_delta_1s={position_count[31],position_count}-{ps9[31],ps9};
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin pos_win_cnt<=0; pos_smp_cnt<=0; pos_stable<=0; pos_eval<=0; pos_delta_r<=0;
                      ps0<=0; ps1<=0; ps2<=0; ps3<=0; ps4<=0; ps5<=0; ps6<=0; ps7<=0; ps8<=0; ps9<=0; end
        else if(!auto_retry) begin pos_win_cnt<=0; pos_smp_cnt<=0; pos_stable<=0; pos_eval<=0; pos_delta_r<=0; end
        else if(ms_tick&&!pos_stable) begin
            if(pos_eval) begin
                pos_eval<=0;
                pos_stable<=(pos_smp_cnt>=10)&&(pos_delta_r<=POS_BAND)&&(pos_delta_r>=-POS_BAND);
            end else if(pos_win_cnt==99) begin
                pos_win_cnt<=0;
                ps9<=ps8; ps8<=ps7; ps7<=ps6; ps6<=ps5; ps5<=ps4;
                ps4<=ps3; ps3<=ps2; ps2<=ps1; ps1<=ps0; ps0<=position_count;
                if(pos_smp_cnt!=10) pos_smp_cnt<=pos_smp_cnt+1'b1;
                pos_delta_r<=pos_delta_1s;   // register the differential, evaluate next cycle
                pos_eval<=1;
            end else pos_win_cnt<=pos_win_cnt+1'b1;
        end
    end
    reg [1:0] return_phase;   // 0=wait both stable, 1=settle delay, 2=returning
    // ---- independent S-curve travel generator (K2 demo, NOT used by the return) ----
    // Velocity is a QUADRATIC function of time: v(u)=6d/T*u(1-u), position follows
    // r(u)=r0+d*(3u^2-2u^3). Shape is an 80-entry ROM (Q15) + a serial shift-and-add
    // multiply: zero hardware multipliers. Completely independent of the pure-PID
    // return path: K2 only STARTS one travel of +-DEMO_DIST counts.
    localparam [6:0] TRAJ_TICKS=7'd50;             // B ticks (50 x 50ms = 2.5s)
    localparam signed [31:0] DEMO_DIST=32'sd1040;  // one K2 travel = one full revolution
    reg [6:0] traj_k;
    reg signed [31:0] traj_r0;                  // travel start position (linear counts)
    reg signed [31:0] traj_d;                   // travel displacement
    reg signed [31:0] traj_r;                   // current trajectory point (B target)
    reg traj_init,traj_adv;                     // one-cycle pulses from the main FSM
    // K2 travel state (round trip: outbound S-curve, then S-curve return - NO PID)
    reg demo_active;                            // round trip in progress
    reg demo_phase;                             // 0=outbound, 1=S-curve return
    reg demo_dir;                               // direction flip: +D / -D alternating
    reg signed [31:0] demo_d;                   // this segment's displacement
    reg [6:0] demo_k;                           // segment progress (0..TRAJ_TICKS)
    // K2 press is a SINGLE-CLOCK pulse; the demo start is only evaluated on the B
    // boundary (every 50ms), so the pulse must be latched or it is always missed.
    reg demo_req;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) demo_req<=0;
        else if(demo_start) demo_req<=1'b1;              // latch the key press
        else if(demo_active||!enable) demo_req<=1'b0;    // consumed / not balancing
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) demo_active_out<=0;
        else demo_active_out<=demo_active;
    end
    // S-curve shape table: shape[k] = round((3u^2-2u^3)*32768), u=k/50 (Q15)
    reg [15:0] shape_rom[0:49];
    initial begin
        shape_rom[0] = 16'd0;
        shape_rom[1] = 16'd39;
        shape_rom[2] = 16'd153;
        shape_rom[3] = 16'd340;
        shape_rom[4] = 16'd596;
        shape_rom[5] = 16'd918;
        shape_rom[6] = 16'd1302;
        shape_rom[7] = 16'd1747;
        shape_rom[8] = 16'd2248;
        shape_rom[9] = 16'd2803;
        shape_rom[10] = 16'd3408;
        shape_rom[11] = 16'd4060;
        shape_rom[12] = 16'd4756;
        shape_rom[13] = 16'd5493;
        shape_rom[14] = 16'd6268;
        shape_rom[15] = 16'd7078;
        shape_rom[16] = 16'd7919;
        shape_rom[17] = 16'd8788;
        shape_rom[18] = 16'd9683;
        shape_rom[19] = 16'd10599;
        shape_rom[20] = 16'd11534;
        shape_rom[21] = 16'd12485;
        shape_rom[22] = 16'd13449;
        shape_rom[23] = 16'd14422;
        shape_rom[24] = 16'd15401;
        shape_rom[25] = 16'd16384;
        shape_rom[26] = 16'd17367;
        shape_rom[27] = 16'd18346;
        shape_rom[28] = 16'd19319;
        shape_rom[29] = 16'd20283;
        shape_rom[30] = 16'd21234;
        shape_rom[31] = 16'd22169;
        shape_rom[32] = 16'd23085;
        shape_rom[33] = 16'd23980;
        shape_rom[34] = 16'd24849;
        shape_rom[35] = 16'd25690;
        shape_rom[36] = 16'd26500;
        shape_rom[37] = 16'd27275;
        shape_rom[38] = 16'd28012;
        shape_rom[39] = 16'd28708;
        shape_rom[40] = 16'd29360;
        shape_rom[41] = 16'd29965;
        shape_rom[42] = 16'd30520;
        shape_rom[43] = 16'd31021;
        shape_rom[44] = 16'd31466;
        shape_rom[45] = 16'd31850;
        shape_rom[46] = 16'd32172;
        shape_rom[47] = 16'd32428;
        shape_rom[48] = 16'd32615;
        shape_rom[49] = 16'd32729;
    end
    // Serial multiply by shift-and-add: d * shape (16 bits) in 17 clocks, NO multiplier
    // at all (DSP blocks are 80% used and must stay with the PID cores).
    reg [4:0] mul_cnt;
    reg signed [31:0] mul_acc,mul_mc;
    reg [15:0] mul_mp;
    reg traj_busy;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin traj_k<=0; traj_r0<=0; traj_d<=0; traj_r<=0;
                      mul_cnt<=0; mul_acc<=0; mul_mc<=0; mul_mp<=0; traj_busy<=0; end
        else begin
            if(traj_init) begin
                // K2 travel: start from the current cart position (linear counts)
                traj_r0<=position_count;
                traj_d<=demo_d;
                traj_k<=0; traj_r<=position_count; traj_busy<=0; mul_cnt<=0;
            end else if(traj_adv&&traj_k<TRAJ_TICKS&&!traj_busy) begin
                traj_k<=traj_k+1'b1;
                mul_mp<=shape_rom[traj_k];
                mul_mc<=traj_d;
                mul_acc<=0; mul_cnt<=0;
                traj_busy<=1;
            end else if(traj_busy) begin
                if(mul_cnt==5'd16) begin
                    traj_busy<=0;
                    traj_r<=traj_r0+(mul_acc>>>15);
                end else begin
                    if(mul_mp[0]) mul_acc<=mul_acc+mul_mc;
                    mul_mc<=mul_mc<<<1;
                    mul_mp<=mul_mp>>1;
                    mul_cnt<=mul_cnt+1'b1;
                end
            end
        end
    end
    // mapped-error jump detection: a ring-boundary wrap makes the error jump ~2*HALF_REV.
    reg signed [32:0] mapped_err_prev;
    wire signed [33:0] err_diff={{1{mapped_err[32]}},mapped_err}-{{1{mapped_err_prev[32]}},mapped_err_prev};
    wire jump_flag=(err_diff>JUMP_THRESH)||(err_diff< -JUMP_THRESH);
    reg [10:0] return_delay;   // 2s settle delay after center-stable (auto_retry only)
    reg signed [31:0] hold_pos;   // frozen capture position; PID brakes back to it during wait/delay
    reg returning_r;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) returning_r<=0;
        else returning_r<=auto_retry&&((return_phase!=2)||(mapped_err>ARRIVED)||(mapped_err< -ARRIVED));
    end
    assign returning=returning_r;
    reg [2:0] stage;
    reg [15:0] count_a,count_b;
    wire due_a=ms_tick&&(count_a>=period_a_ms-1'b1);
    wire due_b=ms_tick&&dual_loop&&(count_b>=period_b_ms-1'b1);
    reg tick_a,tick_b,clear_a,clear_b,run_a_after_b;
    reg pending_clear_a;
    reg [31:0] applied_a,applied_b;
    reg signed [31:0] a_target,a_feedback,b_target,b_feedback;
    reg signed [31:0] sample_ka[0:2],sample_kb[0:2];
    reg signed [31:0] limit_a,limit_b,i_limit_a,i_limit_b;
    reg signed [31:0] sampled_center;
    wire signed [31:0] result_a,result_b;
    wire signed [31:0] inner_limit={24'b0,inner_limit_percent}*32'sd25;
    wire signed [31:0] inner_i_limit={24'b0,inner_i_percent}*32'sd25;
    // Safety consumes the SAME feedback snapshot before either PID is launched.
    assign a_sample_adc=a_feedback[11:0];
    assign pid_pwm_ticks=(enable&&ANGLE_OUTPUT_SIGN<0)?-result_a:enable?result_a:32'sd0;
    PID_Core pid_a(.clk(clk),.rst_n(rst_n),.pid_en(enable),.pid_clear(clear_a),.pid_tick(tick_a),
        .target(a_target),.feedback(a_feedback),.kp_q(sample_ka[0]),.ki_q(sample_ka[1]),.kd_q(sample_ka[2]),
        .out_max(limit_a),.out_min(-limit_a),.i_limit(i_limit_a),.pid_out(result_a),
        .error_out(),.p_out(),.i_out(),.d_out(),.pid_valid(a_done));
    PID_Core pid_b(.clk(clk),.rst_n(rst_n),.pid_en(enable&&dual_loop),.pid_clear(clear_b),.pid_tick(tick_b),
        .target(b_target),.feedback(b_feedback),.kp_q(sample_kb[0]),.ki_q(sample_kb[1]),.kd_q(sample_kb[2]),
        .out_max(limit_b),.out_min(-limit_b),.i_limit(i_limit_b),.pid_out(result_b),
        .error_out(),.p_out(),.i_out(),.d_out(),.pid_valid(b_done));
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            stage<=IDLE; count_a<=0; count_b<=0; a_sample_valid<=0;
            tick_a<=0; tick_b<=0; clear_a<=0; clear_b<=0; run_a_after_b<=0;
            pending_clear_a<=0;
            applied_a<=0; applied_b<=0;
            a_target<=0; a_feedback<=0; b_target<=0; b_feedback<=0; sampled_center<=0;
            return_delay<=0; return_phase<=0; hold_pos<=0; mapped_err_prev<=0; traj_init<=0; traj_adv<=0;
            demo_active<=0; demo_phase<=0; demo_dir<=0; demo_d<=0; demo_k<=0;
            sample_ka[0]<=0; sample_ka[1]<=0; sample_ka[2]<=0;
            sample_kb[0]<=0; sample_kb[1]<=0; sample_kb[2]<=0;
            limit_a<=0; limit_b<=0; i_limit_a<=0; i_limit_b<=0;
            a_goal<=2180; a_real<=0; a_set_ticks<=0; b_goal<=0; b_real<=0; b_set_adc<=0;
        end else begin
            a_sample_valid<=0;
            tick_a<=0; tick_b<=0; clear_a<=0; clear_b<=0;
            traj_init<=0; traj_adv<=0;   // pulses default to zero every cycle
            if(!enable||capture_clear) begin
                stage<=IDLE; count_a<=0; count_b<=0;
                pending_clear_a<=0;
                a_goal<=center_adc; a_real<={20'b0,angle_adc}; a_set_ticks<=0;
                b_goal<=goal_position; b_real<=position_count; b_set_adc<=0;
                a_target<=center_adc; a_feedback<={20'b0,angle_adc};
                b_target<=goal_position; b_feedback<=position_count;
                if(capture_clear) begin
                    clear_a<=1; clear_b<=1;
                    // auto re-swing: wait for center-stable, then 2s delay, then return.
                    // First launch (K1): original behavior, phase=2 (unused).
                    return_phase<=auto_retry?2'd0:2'd2;
                    return_delay<=0;
                    hold_pos<=position_count;   // freeze the capture position for braking
                    mapped_err_prev<=0;
                end
            end else begin
                if(ms_tick) begin
                    count_a<=due_a?16'd0:count_a+1'b1;
                    count_b<=(!dual_loop||due_b)?16'd0:count_b+1'b1;
                    if(auto_retry&&return_phase==0) begin
                        // both stability checks must pass before the delay starts
                        if(center_stable&&pos_stable) begin return_phase<=1; return_delay<=11'd1000; end
                    end else if(auto_retry&&return_phase==1) begin
                        if(return_delay>0) return_delay<=return_delay-1'b1;
                        else begin
                            return_phase<=2;
                            traj_init<=1;   // initialize the S-curve trajectory
                        end
                    end
                end
                if(!dual_loop) begin b_goal<=goal_position; b_real<=position_count; b_set_adc<=0; end
                case(stage)
                    IDLE: if(due_a||due_b) begin
                        // Command completion on this clock is seen on the NEXT boundary.
                        sampled_center<=center_adc;
                        run_a_after_b<=due_a;
                        if(due_a) begin
                            a_target<=center_adc+(dual_loop?CASCADE_SIGN*b_set_adc:32'sd0);
                            a_feedback<={20'b0,angle_adc}; a_sample_valid<=1;
                            sample_ka[0]<=kp_a; sample_ka[1]<=ki_a; sample_ka[2]<=kd_a;
                            limit_a<=inner_limit; i_limit_a<=inner_i_limit;
                            pending_clear_a<=(epoch_a!=applied_a); applied_a<=epoch_a;
                        end
                        if(due_b) begin
                            sample_kb[0]<=kp_b;
                            sample_kb[2]<=kd_b;
                            i_limit_b<={16'b0,outer_i_adc};
                            // K2 demo round trip: outbound S-curve to goal+dir*DEMO_DIST,
                            // then S-curve RETURN to goal_position (no PID in either leg).
                            // Pressing K2 again flips the direction.
                            if(demo_req&&!demo_active&&(!auto_retry||return_phase!=2)) begin
                                demo_active<=1; demo_phase<=0;
                                demo_dir<=~demo_dir;
                                // outbound target = goal + dir*DEMO_DIST, starting now
                                demo_d<=(demo_dir? -DEMO_DIST:DEMO_DIST)+(goal_position-position_count);
                                demo_k<=0; traj_init<=1;
                            end else if(demo_active) begin
                                if(demo_k<TRAJ_TICKS) begin demo_k<=demo_k+1'b1; traj_adv<=1; end
                                else if(demo_phase==0) begin
                                    // outbound finished: S-curve return to the goal position
                                    demo_phase<=1;
                                    demo_d<=goal_position-position_count;
                                    demo_k<=0; traj_init<=1;
                                end else demo_active<=0;   // round trip finished
                            end
                            if(demo_active) begin
                                // demo travel: track the S-curve point (linear coordinates)
                                b_target<=traj_r;
                                b_feedback<=position_count;
                                limit_b<={16'b0,outer_limit_adc};
                                sample_kb[1]<=ki_b;
                            end else if(!auto_retry) begin
                                // FIRST launch (K1): original behavior untouched
                                b_target<=goal_position;
                                b_feedback<=position_count;
                                limit_b<={16'b0,outer_limit_adc};
                                sample_kb[1]<=ki_b;
                            end else if(return_phase!=2) begin
                                // waiting for center-stable (phase 0) or in the 2s settle
                                // delay (phase 1): PID brakes the cart back to the frozen
                                // capture position
                                b_target<=hold_pos;
                                b_feedback<=position_count;
                                limit_b<={16'b0,outer_limit_adc};
                                sample_kb[1]<=ki_b;
                            end else begin
                                // PURE PID return (unchanged): target = goal, feedback =
                                // ring-mapped position, original kp_b/ki_b/kd_b and output
                                // limit. Exactly like changing goal_B.
                                b_target<=goal_position;
                                b_feedback<=mapped_pos;
                                limit_b<={16'b0,outer_limit_adc};
                                sample_kb[1]<=ki_b;
                            end
                            clear_b<=(epoch_b!=applied_b)||jump_flag;
                            applied_b<=epoch_b;
                            mapped_err_prev<=mapped_err;
                            stage<=B_TICK;
                        end else stage<=A_PREP;
                    end
                    B_TICK: begin tick_b<=1; stage<=B_WAIT; end
                    B_WAIT: if(b_done) begin
                        b_goal<=b_target; b_real<=b_feedback; b_set_adc<=result_b;
                        if(run_a_after_b) begin
                            a_target<=sampled_center+CASCADE_SIGN*result_b;
                            stage<=A_PREP;
                        end else stage<=IDLE;
                    end
                    A_PREP: begin clear_a<=pending_clear_a; pending_clear_a<=0; stage<=A_TICK; end
                    A_TICK: begin tick_a<=1; stage<=A_WAIT; end
                    A_WAIT: if(a_done) begin
                        a_goal<=a_target; a_real<=a_feedback;
                        a_set_ticks<=(ANGLE_OUTPUT_SIGN<0)?-result_a:result_a;
                        stage<=IDLE;
                    end
                    default: stage<=IDLE;
                endcase
            end
        end
    end
endmodule




