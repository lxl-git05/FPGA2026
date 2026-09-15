// 2. 波特率时钟输出
`timescale 1ns / 1ps
module div_cnt(
        input wire clk,
        input wire rst_n,
        input wire uart_state,
        input wire [15:0]bps_DR,
        output reg bps_clk
    );
    // 2.1 内部计时器
    reg [15:0] div_cnt ;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            div_cnt <= 16'd0;
        else if (uart_state) begin
            if (div_cnt == bps_DR)
                div_cnt <= 16'd0 ;
            else
                div_cnt <= div_cnt + 1'b1 ;
        end
    end

    // 2.2 波特率时钟输出
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            bps_clk <= 1'b0;
        else if (uart_state) begin
            if (div_cnt == bps_DR)
                bps_clk <= 1'b1 ;
            else
                bps_clk <= 1'b0 ;
        end
    end
endmodule
