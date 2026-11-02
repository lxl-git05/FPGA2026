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
)(input wire clk,rst_n,ms_tick,enable,capture_clear,auto_retry,dual_loop,
    input wire move_enable,
    input wire signed [31:0] move_target,
    input wire [15:0] period_a_ms,period_b_ms,outer_limit_adc,outer_i_adc,
    input wire [7:0] inner_limit_percent,inner_i_percent,
    input wire signed [31:0] center_adc,goal_position,position_count,
    input wire [11:0] angle_adc,
    input wire signed [31:0] kp_a,ki_a,kd_a,kp_b,ki_b,kd_b,
    input wire [31:0] epoch_a,epoch_b,
    output wire signed [31:0] pid_pwm_ticks,
    output reg signed [31:0] a_goal,a_real,a_set_ticks,b_goal,b_real,b_set_adc,
    output wire returning,
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
    reg [3:0] pos_wr;
    reg [3:0] pos_smp_cnt;
    reg signed [31:0] pos_hist[0:9];
    reg pos_stable;
    reg pos_eval;                       // one-cycle pipeline stage for the stability check
    reg signed [32:0] pos_delta_r;      // registered 1s differential
    wire signed [32:0] pos_delta_1s={position_count[31],position_count}-{pos_hist[pos_wr][31],pos_hist[pos_wr]};
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin pos_win_cnt<=0; pos_wr<=0; pos_smp_cnt<=0; pos_stable<=0; pos_eval<=0; pos_delta_r<=0; end
        else if(!auto_retry) begin pos_win_cnt<=0; pos_wr<=0; pos_smp_cnt<=0; pos_stable<=0; pos_eval<=0; pos_delta_r<=0; end
        else if(ms_tick&&!pos_stable) begin
            if(pos_eval) begin
                pos_eval<=0;
                pos_stable<=(pos_smp_cnt>=10)&&(pos_delta_r<=POS_BAND)&&(pos_delta_r>=-POS_BAND);
            end else if(pos_win_cnt==99) begin
                pos_win_cnt<=0;
                pos_hist[pos_wr]<=position_count;
                pos_wr<=(pos_wr==9)?4'd0:pos_wr+1'b1;
                if(pos_smp_cnt!=10) pos_smp_cnt<=pos_smp_cnt+1'b1;
                pos_delta_r<=pos_delta_1s;   // register the differential, evaluate next cycle
                pos_eval<=1;
            end else pos_win_cnt<=pos_win_cnt+1'b1;
        end
    end
    reg [1:0] return_phase;   // 0=wait both stable, 1=2s settle delay, 2=returning
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
            return_delay<=0; return_phase<=0; hold_pos<=0; mapped_err_prev<=0;
            sample_ka[0]<=0; sample_ka[1]<=0; sample_ka[2]<=0;
            sample_kb[0]<=0; sample_kb[1]<=0; sample_kb[2]<=0;
            limit_a<=0; limit_b<=0; i_limit_a<=0; i_limit_b<=0;
            a_goal<=2180; a_real<=0; a_set_ticks<=0; b_goal<=0; b_real<=0; b_set_adc<=0;
        end else begin
            a_sample_valid<=0;
            tick_a<=0; tick_b<=0; clear_a<=0; clear_b<=0;
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
                        else return_phase<=2;
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
                            if(!auto_retry) begin
                                // FIRST launch (K1): original behavior, or K2 trajectory target.
                                if(move_enable) b_target<=move_target;
                                else            b_target<=goal_position;
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
                                // PURE PID return: exactly like changing goal_B - original
                                // kp_b/ki_b/kd_b and original output limit, no gain switch,
                                // no Ki gate, no brake cap. The PID converges by itself.
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
