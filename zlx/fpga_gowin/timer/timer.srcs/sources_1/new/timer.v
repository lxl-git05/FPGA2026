`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/09/17 19:57:02
// Design Name: 
// Module Name: timer
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


module timer(
input clk,rst,
input [31:0]t,
output reg flag
    );
    parameter M=250_000;
    reg [31:0]count;
    parameter ms=1000;
    always @(posedge clk,negedge rst) 
    begin
    if(~rst)
    begin
    count<=0;
    flag<=0;
    end
    else if(~flag)
    begin
    if(count==(M-t)*ms-1)
    flag<=1;
    else
    count<=count+1'b1;
    end    
    end
endmodule
