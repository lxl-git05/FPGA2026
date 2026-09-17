`timescale 1ns / 1ps
module uart_data_rx_tb;
    parameter integer DATA_WIDTH = 32 ;

    // 1. 例化RX
    //Ports
    reg clk;
    reg rst_n;
    wire uart_tx_rx;
    wire [DATA_WIDTH - 1 : 0] data_rx;
    reg [2:0] Baud_Set = 3'd0 ;
    wire rx_Done;
    wire timeout_flag;

    uart_data_rx  #(.DATA_WIDTH(DATA_WIDTH))
    uart_data_rx_inst (
        .clk(clk),
        .rst_n(rst_n),
        .uart_rx(uart_tx_rx),
        .data(data_rx),
        .Baud_Set(Baud_Set),
        .rx_Done(rx_Done),
        .timeout_flag(timeout_flag)
    );

    // 2. 例化TX
    reg [DATA_WIDTH - 1 : 0] data_tx;
    reg send_en ;
    wire Tx_Done ;
    wire uart_state ;
    uart_data_tx #(.DATA_WIDTH(DATA_WIDTH))  
    uart_data_tx_inst 
    (
        .clk(clk),
        .rst_n(rst_n),
        .data(data_tx),
        .send_en(send_en),
        .Baud_Set(Baud_Set),
        .uart_tx(uart_tx_rx),
        .Tx_Done(Tx_Done),
        .uart_state(uart_state)
    );

    // 时钟
    initial clk = 0 ;
    always #10  clk = ! clk ;

    // 逻辑
    initial 
    begin
        rst_n = 0;
        data_tx = 0 ;
        send_en = 0 ;
        #21 ;
        rst_n = 1 ;
        // 发送0x12345678
        @(negedge clk) ;
        data_tx = 32'h12345678 ;
        send_en = 1 ;
        @(negedge clk) ;
        send_en = 0 ;

        @(posedge Tx_Done) ;

        // 发送0x5A310001
        @(negedge clk) ;
        data_tx = 32'h5A310001 ;
        send_en = 1 ;
        @(negedge clk) ;
        send_en = 0 ;
    end

endmodule