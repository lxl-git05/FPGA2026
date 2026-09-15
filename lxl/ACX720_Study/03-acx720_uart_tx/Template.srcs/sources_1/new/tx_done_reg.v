// 4. 一次TX输出完成标志
`timescale 1ns / 1ps
module tx_done_reg(
        input wire clk,
        input wire rst_n,
        input wire [3:0] bps_cnt,
        output reg tx_done
    );
    // 判断输出是否完成
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            tx_done <= 1'b0 ;
        else if (bps_cnt == 4'd11) // bps_cnt在11计数值的时候会在下一个clk立即变成0,而不是等到下一个bps_clk
            tx_done <= 1'b1 ;
        else
            tx_done <= 1'b0 ;
    end
endmodule
