`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/09/23 10:04:30
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


module tb(
    );
    reg clk, rst;
    reg [7:0] data;
    wire uart_tx, led;

    // 缩短参数便于仿真
    uart_tx #(
        .M(2000),      // 40us 触发一次
        .M1(100)       // 2us 位周期
    ) uut (
        .clk(clk),
        .rst(rst),
        .data(data),
        .uart_tx(uart_tx),
        .led(led)
    );

    initial clk = 0;
    always #10 clk = ~clk;   // 50MHz

    initial begin
        rst = 0;
        data = 8'hA5;
        #100;
        rst = 1;

        #100000;
        data = 8'h3C;
        #100000;
        data = 8'hFF;
        #100000;
        $stop;
    end

   
endmodule
