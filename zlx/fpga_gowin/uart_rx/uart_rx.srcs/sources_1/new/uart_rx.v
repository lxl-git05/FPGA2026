`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/09/28 12:33:50
// Design Name: 
// Module Name: uart_rx
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


module uart_rx(
input clk,rst,
input  rx,
output reg done,
output reg [7:0]data
    );
    parameter M=50_000_000;
    parameter baud=9600;
    parameter M1=M/baud-1;
    reg flag,d;
    reg [3:0]s;//状态
    reg [29:0]counter1; 
    wire rx_done;
    wire neg_rx;
    reg d1,d0;
    always @(posedge clk)//消除亚稳态
    begin
    d0<=rx;
    end
    always @(posedge clk)
    begin
    d1<=d0;
    end
    always @(posedge clk)//无复位D触发器
    begin
    d<=d1; 
    end
    assign neg_rx=(!d1)&&d;
    always @(posedge clk,negedge rst)//波特率计数器
    begin
    if(~rst)
    begin
    counter1<=0;
    end
    else if(flag)
    begin
    if(counter1==M1)
    begin
    counter1<=0;
    end
    else if(counter1<M1)
    counter1<=counter1+1;
    end
    else
    counter1<=0;
    end
    always @(posedge clk,negedge rst)//位计数器
    begin
    if(~rst)
    s<=0;
    else if(counter1==M1)
    begin
    if(s==9)
    s<=0;
    else 
    s<=s+1;
    end
    end
    
    always @(posedge clk,negedge rst)//使能
    begin
    if(~rst)
    flag<=0;
    else if(neg_rx)
    flag<=1;
    else if((counter1==M1)&&(s==9))
    flag<=0;
    else if((counter1==M1/2)&&(s==0)&&(d1==1))//检测毛刺
    flag<=0;
    end 
    always @(posedge clk,negedge rst )//位接收
    begin
    if(~rst)
    begin
    data<=8'b0;
    end
    else if(counter1==M1/2)
     begin
    case(s)
    1:data[0]<=d1;
    2:data[1]<=d1;
    3:data[2]<=d1;
    4:data[3]<=d1;
    5:data[4]<=d1;
    6:data[5]<=d1;
    7:data[6]<=d1;
    8:data[7]<=d1;
    default data<=data;
    endcase
    end
    end
    assign rx_done=(counter1==M1)&&(s==9);
    always @(posedge clk)
    begin
    done<=rx_done;
    end
endmodule
