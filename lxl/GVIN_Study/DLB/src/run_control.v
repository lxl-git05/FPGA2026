`timescale 1ns / 1ps
// K1 toggles running. Faults latch until conditions clear and a NEW K1 press occurs.
module run_control(input wire clk,rst_n,key_press,sensor_ok,position_safe,config_ready,
    input wire auto_start,fault_now,capture_request,swing_timed_out,
    input wire [3:0] fault_reason,
    input wire signed [31:0] encoder_count,pid_pwm_ticks,swing_pwm_ticks,
    output reg [2:0] state, output reg [3:0] fault_code,
    output reg signed [31:0] position_origin,
    output reg capture_clear,
    output wire active,balancing,swing_enable,motor_enable,
    output wire signed [31:0] motor_pwm_ticks);
    localparam STOPPED=0,MANUAL_WAIT=1,AUTO_SWING=2,BALANCE=3,FAULT=4;
    assign active=(state==MANUAL_WAIT)||(state==AUTO_SWING)||(state==BALANCE);
    assign balancing=(state==BALANCE);
    assign swing_enable=(state==MANUAL_WAIT)||(state==AUTO_SWING);
    assign motor_enable=active&&sensor_ok&&!fault_now&&!swing_timed_out&&!key_press;
    assign motor_pwm_ticks=!motor_enable?32'sd0:
                           (state==AUTO_SWING)?swing_pwm_ticks:
                           (state==BALANCE)?pid_pwm_ticks:32'sd0;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin state<=STOPPED; fault_code<=0; position_origin<=0; capture_clear<=0; end
        else begin
            capture_clear<=0;
            if(active&&(fault_now||swing_timed_out)) begin
                state<=FAULT; fault_code<=swing_timed_out?4'd5:fault_reason;
            end else if(key_press) begin
                if(active) state<=STOPPED;
                else if(sensor_ok&&position_safe&&config_ready) begin
                    position_origin<=encoder_count; fault_code<=0;
                    state<=auto_start?AUTO_SWING:MANUAL_WAIT;
                end
            end else if(swing_enable&&capture_request) begin
                state<=BALANCE; capture_clear<=1;
            end
        end
    end
endmodule
