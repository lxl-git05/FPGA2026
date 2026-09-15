// 3. 波特率计数器: bit_cnt = 0,1,2,...,11,0
`timescale 1ns / 1ps
module bps_cnt(
        input wire clk,
        input wire rst_n,
        input wire bps_clk,
        output reg [3:0]bps_cnt // 0-11
    );
    // 根据波特率时钟bps_clk产生cnt,clk纯粹是计数器激活always用的
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            bps_cnt <= 4'b0 ;
        else if (bps_clk) // 注意: 这里是波特率clk才能cnt++,并且由于bps_clk是在clk上升沿到达bps_DR,而此时clk上升沿结束，所以bps_cnt只能等到下一次clk才能++
            bps_cnt <= bps_cnt + 1'b1 ;
        else if (bps_cnt == 4'd11)
            bps_cnt <= 4'b0 ;
        else
            bps_cnt <= bps_cnt ;
    end
endmodule
