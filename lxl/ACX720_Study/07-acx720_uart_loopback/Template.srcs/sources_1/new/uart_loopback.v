// 串口回环检测
`timescale 1ns / 1ps
module uart_loopback(
        input wire clk ,
        input wire rst_n ,
        input wire uart_rx ,

        output wire uart_tx 
    );

    parameter integer DATA_WIDTH = 32 ;
    wire [DATA_WIDTH - 1 : 0] data ;
    wire rx_Done ;

    // 例化TX
    uart_data_tx  #(.DATA_WIDTH(DATA_WIDTH))
    uart_data_tx_inst (
        .clk(clk),
        .rst_n(rst_n),
        .data(data),
        .send_en(rx_Done),
        .Baud_Set(3'd0),
        .uart_tx(uart_tx),
        .Tx_Done(),
        .uart_state()
    );

    // 例化RX
    uart_data_rx  #(.DATA_WIDTH(DATA_WIDTH))
    uart_data_rx_inst (
        .clk(clk),
        .rst_n(rst_n),
        .uart_rx(uart_rx),
        .data(data),
        .Baud_Set(3'd0),
        .rx_Done(rx_Done),
        .timeout_flag()
    );
endmodule
