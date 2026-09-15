// 6. 10路选择器发送Tx_Data
`timescale 1ns / 1ps
module mux_tx
    #(
        parameter integer START_BIT = 0 ,
        parameter integer  STOP_BIT = 1 
    )
    (
        input wire clk,
        input wire rst_n,
        input wire [3:0] bps_cnt,
        input wire [7:0] data_byte_reg,
        output reg uart_tx  // 每个 波特率周期clk 只发送一位
    );

    // 10路选择与发送
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            uart_tx <= 1'b1 ;   // 空闲的时候是1
        case (bps_cnt)
            0 : uart_tx <= 1'b1 ;   // 空闲位(我在想有没有必要?)
            1 : uart_tx <= START_BIT ;
            2 : uart_tx <= data_byte_reg[0] ;   // LSB顺序,所以是从低位开始
            3 : uart_tx <= data_byte_reg[1] ;
            4 : uart_tx <= data_byte_reg[2] ;
            5 : uart_tx <= data_byte_reg[3] ;
            6 : uart_tx <= data_byte_reg[4] ;
            7 : uart_tx <= data_byte_reg[5] ;
            8 : uart_tx <= data_byte_reg[6] ;
            9 : uart_tx <= data_byte_reg[7] ;
            10: uart_tx <= STOP_BIT ;
            default : uart_tx <= 1'b1 ;
        endcase
    end
endmodule
