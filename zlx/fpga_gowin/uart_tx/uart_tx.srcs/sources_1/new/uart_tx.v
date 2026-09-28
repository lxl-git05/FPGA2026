`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/09/23 08:48:25
// Design Name: 
// Module Name: uart_tx
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


module uart_tx(
input clk,rst,
input [7:0]data,
output reg uart_tx,
output reg led
    );
    parameter M=50_000_000;
    parameter baud=9600;
    parameter M1=M/baud-1;
    reg [31:0]counter;
    reg [29:0]counter1;
    reg flag;
    reg [7:0]d;
    reg [3:0]s;
    always @(posedge clk,negedge rst)
    begin
    if(~rst)
    begin
    counter<=0;
    end
    else if(counter==M-1)
    begin
    counter<=0;
    end
    else if(counter<M-1)
    begin
    counter<=counter+1;
    end
    end
    always @(posedge clk,negedge rst)//D触发器
    begin
    if(~rst)
    d<=8'b0;
    else if(counter==M-1)
    d<=data;
    end
    always @(posedge clk,negedge rst)//波特率计数器
    begin
    if(~rst)
    begin
    counter1<=0;
    end
    else if(flag)
    begin
    if(counter1==M1-1)
    begin
    counter1<=0;
    end
    else if(counter1<M1-1)
    counter1<=counter1+1;
    end
    else
    counter1<=0;
    end
  always @(posedge clk,negedge rst)//位计数器
    begin
    if(~rst)
    s<=0;
    else if(counter1==M1-1)
    begin
    if(s==9)
    s<=0;
    else 
    s<=s+1;
    end
    end
    always @(posedge clk,negedge rst )//位发送
    begin
    if(~rst)
    begin
    uart_tx<=1;
    end
    else if(flag)
     begin
    case(s)
    0:uart_tx<=0;
    1:uart_tx<=d[0];
    2:uart_tx<=d[1];
    3:uart_tx<=d[2];
    4:uart_tx<=d[3];
    5:uart_tx<=d[4];
    6:uart_tx<=d[5];
    7:uart_tx<=d[6];
    8:uart_tx<=d[7];
    9:uart_tx<=1;
    default uart_tx<=uart_tx;
    endcase
    end
    end
    always @(posedge clk,negedge rst)//led状态反转
    begin
    if(~rst)
    led<=0;
    else if((s==9)&&(counter1==M1-1))
    led<=~led;
    end
    always @(posedge clk,negedge rst)//flag状态反转
    begin
    if(~rst)
    flag<=0;
    else if(counter==M-1)
    flag<=1;
    else if((s==9)&&(counter1==M1-1))
    flag<=0;
    end
endmodule
