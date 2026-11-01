`timescale 1ns / 1ps
// Initial +kick/-kick, then three-point peak decisions every judge_ms.
// Invalid angle resets history, not pulse timers or raw sensor freshness.
module swing_up(input wire clk,rst_n,ms_tick,enable,auto_mode,
    input wire angle_valid,capture_allowed,
    input wire [11:0] angle_adc,capture_adc,
    input wire signed [31:0] center_adc,
    input wire [7:0] kick_percent,
    input wire [15:0] kick_ms,judge_ms,swing_timeout_ms,
    output wire signed [31:0] swing_pwm_ticks,
    output reg capture_request, output wire timed_out);
    reg previous_enable;
    reg [1:0] phase;
    reg kick_negative;
    reg [15:0] remaining,judge_count,total_ms;
    reg [1:0] history_count;
    reg [1:0] capture_count;
    reg [11:0] angle0,angle1;
    wire signed [31:0] kick_ticks={24'b0,kick_percent}*32'sd25;
    assign swing_pwm_ticks=enable&&auto_mode&&phase!=0?
        ((kick_negative^(phase==2))?-kick_ticks:kick_ticks):32'sd0;
    assign timed_out=enable&&auto_mode&&(total_ms>=swing_timeout_ms);
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            previous_enable<=0; phase<=0; kick_negative<=0; remaining<=0;
            judge_count<=0; total_ms<=0; history_count<=0; capture_count<=0;
            angle0<=0; angle1<=0; capture_request<=0;
        end else begin
            previous_enable<=enable; capture_request<=0;
            if(!enable) begin
                phase<=0; total_ms<=0; judge_count<=0; history_count<=0; capture_count<=0;
            end else if(!previous_enable) begin
                phase<=auto_mode?1:0; kick_negative<=0; remaining<=kick_ms;
                total_ms<=0; judge_count<=0; history_count<=0; capture_count<=0;
            end else begin
                if(!angle_valid) begin history_count<=0; capture_count<=0; end
                if(ms_tick) begin
                    if(total_ms!=16'hffff) total_ms<=total_ms+1'b1;
                    if(phase!=0) begin
                        if(remaining>1) remaining<=remaining-1'b1;
                        else if(phase==1) begin phase<=2; remaining<=kick_ms; end
                        else begin phase<=0; judge_count<=0; history_count<=0; capture_count<=0; end
                    end else if(judge_count>=judge_ms-1'b1) begin
                        judge_count<=0;
                        if(angle_valid) begin
                            angle1<=angle0; angle0<=angle_adc;
                            if(history_count<2) history_count<=history_count+1'b1;
                            if(capture_allowed) begin
                                if(capture_count>=1) capture_request<=1;
                                else capture_count<=capture_count+1'b1;
                            end else capture_count<=0;
                            if(auto_mode && history_count>=2) begin
                                if(angle_adc>center_adc+capture_adc && angle0>center_adc+capture_adc &&
                                   angle1>center_adc+capture_adc && angle0<angle_adc && angle0<angle1) begin
                                    phase<=1; kick_negative<=0; remaining<=kick_ms;
                                end
                                if($signed({20'b0,angle_adc})<center_adc-$signed({20'b0,capture_adc}) &&
                                   $signed({20'b0,angle0})<center_adc-$signed({20'b0,capture_adc}) &&
                                   $signed({20'b0,angle1})<center_adc-$signed({20'b0,capture_adc}) &&
                                   angle0>angle_adc && angle0>angle1) begin
                                    phase<=1; kick_negative<=1; remaining<=kick_ms;
                                end
                            end
                        end
                    end else judge_count<=judge_count+1'b1;
                end
            end
        end
    end
endmodule
