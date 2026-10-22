`timescale 1ns / 1ps
// Two independent 8-clock PID cores. All logic uses clk; ms_tick is only an enable.
// Coincident deadlines: snapshot both inputs, B completes first, then A uses NEW B result.
module cascade_control #(
    parameter integer CASCADE_SIGN=-1, parameter integer ANGLE_OUTPUT_SIGN=1
)(input wire clk,rst_n,ms_tick,enable,capture_clear,dual_loop,
    input wire [15:0] period_a_ms,period_b_ms,outer_limit_adc,outer_i_adc,
    input wire [7:0] inner_limit_percent,inner_i_percent,
    input wire signed [31:0] center_adc,goal_position,position_count,
    input wire [11:0] angle_adc,
    input wire signed [31:0] kp_a,ki_a,kd_a,kp_b,ki_b,kd_b,
    input wire [31:0] epoch_a,epoch_b,
    output wire signed [31:0] pid_pwm_ticks,
    output reg signed [31:0] a_goal,a_real,a_set_ticks,b_goal,b_real,b_set_adc,
    output wire a_done,b_done,
    output reg a_sample_valid, output wire [11:0] a_sample_adc);
    localparam IDLE=0,B_TICK=1,B_WAIT=2,A_TICK=3,A_WAIT=4,A_PREP=5;
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
                if(capture_clear) begin clear_a<=1; clear_b<=1; end
            end else begin
                if(ms_tick) begin
                    count_a<=due_a?16'd0:count_a+1'b1;
                    count_b<=(!dual_loop||due_b)?16'd0:count_b+1'b1;
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
                            b_target<=goal_position; b_feedback<=position_count;
                            sample_kb[0]<=kp_b; sample_kb[1]<=ki_b; sample_kb[2]<=kd_b;
                            limit_b<={16'b0,outer_limit_adc}; i_limit_b<={16'b0,outer_i_adc};
                            clear_b<=(epoch_b!=applied_b); applied_b<=epoch_b;
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
