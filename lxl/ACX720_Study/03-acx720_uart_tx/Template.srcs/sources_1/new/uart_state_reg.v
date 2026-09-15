// 5. 串口TX忙标志位,忙的时候是0,空闲的时候是1
`timescale 1ns / 1ps
module uart_state_reg(
        input wire clk,
        input wire rst_n,
        input wire [3:0] bps_cnt,
        input wire send_en,
        output reg uart_state   // 忙的时候是0
    );
    // 忙的时候是0,或者被关闭的时候也是0
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            uart_state <= 1'b0 ;
        else if (send_en == 1'b1)   // send_en也只是一个周期就重新变成0
            uart_state <= 1'b1 ;
        else if (bps_cnt == 4'd11)  // 工作状态结束,等待下一个send_en尖峰
            uart_state <= 1'b0 ;
        else
            uart_state <= uart_state ;
    end
endmodule
