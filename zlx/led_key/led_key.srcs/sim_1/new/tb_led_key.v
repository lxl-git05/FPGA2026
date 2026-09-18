`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/09/16 11:21:22
// Design Name: 
// Module Name: tb_led_key
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


module tb_led_key(

    );
    reg  [7:0] key;
    wire [7:0] led;
    led_key uut(key,led);
    initial begin
        // 初始所有按键释放（高电平）
        key = 8'b1111_1111;
        #10;

        // 逐个按下按键，观察 LED
        key = 8'b1111_1110; #10;  // 按下第 0 位
        key = 8'b1111_1101; #10;  // 按下第 1 位
        key = 8'b1111_1011; #10;  // 按下第 2 位
        key = 8'b1111_0111; #10;  // 按下第 3 位
        key = 8'b1110_1111; #10;  // 按下第 4 位
        key = 8'b1101_1111; #10;  // 按下第 5 位
        key = 8'b1011_1111; #10;  // 按下第 6 位
        key = 8'b0111_1111; #10;  // 按下第 7 位

        // 同时按下多个按键
        key = 8'b0000_0000; #10;
        key = 8'b1010_1010; #10;

        $finish;
    end
endmodule
