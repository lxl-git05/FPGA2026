// 1. 波特率查表器
`timescale 1ns / 1ps
module DR_LUT(
        input  wire clk,
        input  wire rst_n,
        input  wire [2:0]  baud_set,
        output reg  [15:0] bps_DR
    );
    // 波特率选择
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            bps_DR <= 16'd5207;
        else 
            case (baud_set)
                0 : bps_DR <= 16'd5207; // 9600bps/s
                1 : bps_DR <= 16'd2603;
                2 : bps_DR <= 16'd1301;
                3 : bps_DR <= 16'd867 ;
                4 : bps_DR <= 16'd433 ;
                default: bps_DR <= 16'd5207;
            endcase
    end
endmodule
