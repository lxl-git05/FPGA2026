`timescale 1ns / 1ps

module adc(
input clk,rst,Dout,go,
input [2:0]addr,
output reg Din,sclk,csn,done,
output reg [11:0] data
    );
    parameter Clk_F=50_000_000;
    parameter Sclk_F=12_500_000;
    parameter M=Clk_F/(Sclk_F*2)-1;
    reg [7:0]counter;
    reg [5:0]state;
    reg [11:0]r_data;
    reg [2:0]r_addr;
    reg flag;//计数器使能使能
    always @(posedge clk,negedge rst)
    begin
    if(~rst)
    flag<=0;
    else if(go)
    flag<=1;
    else if((state==34)&&(counter==M))
    flag<=0;
    else
    flag<=flag;
    end
    always @(posedge clk,negedge rst)//锁存
    begin
    if(go)
    r_addr<=addr;
    else
    r_addr<=r_addr;
    end
    always @(posedge clk,negedge rst)//最小时间单位计数器
    begin
    if(~rst)
    counter<=0;
    else if(flag)
    begin 
    if(counter<M)
    counter<=counter+1;
    else if(counter==M)
    counter<=0;
    end
    end
    always @(posedge clk,negedge rst)//状态计数器
    begin
    if(~rst)
    state<=0;
    else if(counter==M)
    begin
    if(state<34)
    state<=state+1;
    else if(state==34)
    state<=0;
    end
    else 
    state<=state;
    end
    always @(posedge clk,negedge rst)
    begin
    if(~rst)
    begin
    data<=0;
    sclk<=1;
    Din<=1;
    csn<=1;
    end
    else if(counter==M)
    case(state)
    0:begin csn<=1; sclk<=1;end
    1:begin csn<=0;end
    2:begin sclk<=0;end
    3:begin sclk<=1;end
    4:begin sclk<=0;end
    5:begin sclk<=1;end
    6:begin Din<=r_addr[2]; sclk<=0;end
    7:begin sclk<=1;end
    8:begin Din<=r_addr[1]; sclk<=0;end
    9:begin sclk<=1;end
    10:begin Din<=r_addr[0];sclk<=0;end
    11:begin sclk<=1;r_data[11]<=Dout;end
    12:begin sclk<=0;end
    13:begin sclk<=1;r_data[10]<=Dout;end
    14:begin sclk<=0;end
    15:begin sclk<=1;r_data[9]<=Dout;end
    16:begin sclk<=0;end
    17:begin sclk<=1;r_data[8]<=Dout;end
    18:begin sclk<=0;end
    19:begin sclk<=1;r_data[7]<=Dout;end
    20:begin sclk<=0;end
    21:begin sclk<=1;r_data[6]<=Dout;end
    22:begin sclk<=0;end
    23:begin sclk<=1;r_data[5]<=Dout;end
    24:begin sclk<=0;end
    25:begin sclk<=1;r_data[4]<=Dout;end
    26:begin sclk<=0;end
    27:begin sclk<=1;r_data[3]<=Dout;end
    28:begin sclk<=0;end
    29:begin sclk<=1;r_data[2]<=Dout;end
    30:begin sclk<=0;end
    31:begin sclk<=1;r_data[1]<=Dout;end
    32:begin sclk<=0;end
    33:begin sclk<=1;r_data[0]<=Dout;end
    34:begin csn<=1;end
    endcase
    end
    always @(posedge clk,negedge rst)
    begin
    if(~rst)
    begin
    data<=0;
    done<=0;
    end
    else if((state==34)&&(counter==M))
    begin
    done<=1;
    data<=r_data;
    end
    else begin
    done<=0;
    data<=data;
    end
    end
endmodule
