`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/09/16 11:18:50
// Design Name: 
// Module Name: led_key
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


module led_key(
input [7:0]key,
output reg [7:0]led
    );
    always @(*)
    begin
    led<=~key;
    end
endmodule
