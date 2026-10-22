`timescale 1ns / 1ps
// 3PA1030, forwarded 25MHz. Capture previous conversion before next forwarded edge.
// Raw 62.5us samples are checked BEFORE the 16-sample/1ms average.
module adc_frontend #(
    parameter SAMPLE_TICKS=3125, parameter AVG_LOG2=4
)(input wire clk,rst_n, input wire [9:0] adc_data_in, input wire adc_otr,
    input wire [11:0] rail_low,rail_high,
    output reg adc_clk, output wire adc_oe_n,
    output reg [11:0] raw_adc,angle_adc,
    output reg raw_valid,raw_otr,window_valid,angle_valid);
    reg [9:0] captured_data;
    reg captured_otr;
    reg [$clog2(SAMPLE_TICKS)-1:0] sample_timer;
    reg [AVG_LOG2-1:0] sample_count;
    reg [12+AVG_LOG2-1:0] sample_sum;
    reg [11:0] minimum,maximum;
    reg window_bad;
    wire [11:0] code={captured_data,2'b00};
    wire sample_bad=(code<=rail_low)||(code>=rail_high)||captured_otr;
    wire [11:0] next_min=(code<minimum)?code:minimum;
    wire [11:0] next_max=(code>maximum)?code:maximum;
    wire discontinuity=({1'b0,next_max}-{1'b0,next_min})>=13'd2048;
    wire [12+AVG_LOG2-1:0] sum_next=sample_sum+code;
    assign adc_oe_n=!rst_n;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin adc_clk<=0; captured_data<=0; captured_otr<=0; end
        else begin
            adc_clk<=!adc_clk;
            if(!adc_clk) begin captured_data<=adc_data_in; captured_otr<=adc_otr; end
        end
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            sample_timer<=0; sample_count<=0; sample_sum<=0;
            minimum<=4095; maximum<=0; window_bad<=0;
            raw_adc<=0; raw_valid<=0; raw_otr<=0; angle_adc<=0;
            window_valid<=0; angle_valid<=0;
        end else begin
            raw_valid<=0; window_valid<=0;
            if(sample_timer==SAMPLE_TICKS-1) begin
                sample_timer<=0; raw_adc<=code; raw_otr<=captured_otr; raw_valid<=1;
                if(sample_bad || discontinuity) angle_valid<=0;
                if(sample_count==(1<<AVG_LOG2)-1) begin
                    // Bad windows expose latest raw code for observation, never the false mean.
                    angle_adc<=(window_bad||sample_bad||discontinuity)?code:(sum_next>>AVG_LOG2);
                    angle_valid<=!(window_bad||sample_bad||discontinuity);
                    window_valid<=1; sample_count<=0; sample_sum<=0;
                    minimum<=4095; maximum<=0; window_bad<=0;
                end else begin
                    sample_count<=sample_count+1'b1; sample_sum<=sum_next;
                    minimum<=next_min; maximum<=next_max;
                    window_bad<=window_bad||sample_bad||discontinuity;
                end
            end else sample_timer<=sample_timer+1'b1;
        end
    end
endmodule
