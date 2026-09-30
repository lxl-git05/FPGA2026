`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2026/09/30 10:40:47
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


module tb(   );
reg clk,rst,go,Dout;
reg [2:0]addr;
wire done,sclk,csn,Din;
wire [11:0]data;
adc uut(clk,rst,Dout,go,addr,Din,sclk,csn,done,data);
initial clk=1;
always #10 clk=~clk;
initial begin
rst=0;
go=0;
addr=0;
#201
rst=1;
#200
go=1;
addr=3;
#20
go=0;
wait(!csn);
@(negedge sclk);
Dout=0;//15
@(negedge sclk);
Dout=0;//14
@(negedge sclk);
Dout=0;//13
@(negedge sclk);
Dout=0;//12
@(negedge sclk);
Dout=1;//11
@(negedge sclk);
Dout=0;//10
@(negedge sclk);
Dout=0;//9
@(negedge sclk);
Dout=0;//8
@(negedge sclk);
Dout=0;//7
@(negedge sclk);
Dout=1;//6
@(negedge sclk);
Dout=0;//5
@(negedge sclk);
Dout=0;//4
@(negedge sclk);
Dout=0;//3
@(negedge sclk);
Dout=0;//2
@(negedge sclk);
Dout=1;//1
@(negedge sclk);
Dout=0;//0
wait(csn);
#20000;
go=1;
addr=7;
#20
go=0;
wait(!csn);
@(negedge sclk);
Dout=0;//15
@(negedge sclk);
Dout=0;//14
@(negedge sclk);
Dout=0;//13
@(negedge sclk);
Dout=0;//12
@(negedge sclk);
Dout=0;//11
@(negedge sclk);
Dout=1;//10
@(negedge sclk);
Dout=0;//9
@(negedge sclk);
Dout=1;//8
@(negedge sclk);
Dout=0;//7
@(negedge sclk);
Dout=0;//6
@(negedge sclk);
Dout=1;//5
@(negedge sclk);
Dout=1;//4
@(negedge sclk);
Dout=0;//3
@(negedge sclk);
Dout=1;//2
@(negedge sclk);
Dout=1;//1
@(negedge sclk);
Dout=0;//0
wait(csn);
#2200
$stop;
end

endmodule
