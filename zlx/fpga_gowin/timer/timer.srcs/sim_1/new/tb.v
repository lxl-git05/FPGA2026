`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/09/17 20:20:30
// Design Name: 
// Module Name: tb
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module tb();
    reg clk;
    reg rst;
    reg [31:0] t;
    wire flag;
    timer uut (
        .clk(clk),
        .rst(rst),
        .t(t),
        .flag(flag)
    );
    defparam uut.ms=1;
    // 50 MHz 时钟，周期 20 ns
    initial clk = 0;
    always #10 clk = ~clk;

    initial begin
        // 初始化
        rst = 0;
        t = 0;
        #40;                    // 保持复位至少两个时钟周期
        rst = 1;                // 释放复位
        #6_000_000;
        rst = 0;                // 重新复位
        #40;
        t = 50_000;                  // 设置 t = 5
        rst = 1;
        #4_000_000;
         $finish;
    end
endmodule
