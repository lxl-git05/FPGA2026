`timescale 1ns / 1ps
module uart_data_tx_tb;
    // Parameters
    parameter integer DATA_WIDTH = 32 ;
    // Ports
    reg clk;
    reg rst_n;
    reg [DATA_WIDTH - 1 : 0] data;
    reg send_en;
    reg [2:0] Baud_Set;
    wire uart_tx;
    wire Tx_Done;
    wire uart_state;

    uart_data_tx #(.DATA_WIDTH(DATA_WIDTH))  
    uart_data_tx_inst 
    (
        .clk(clk),
        .rst_n(rst_n),
        .data(data),
        .send_en(send_en),
        .Baud_Set(Baud_Set),
        .uart_tx(uart_tx),
        .Tx_Done(Tx_Done),
        .uart_state(uart_state)
    );

    initial clk = 0 ;
    always #10  clk = ! clk ;

    // 仿真逻辑
    initial 
    begin
        // 初始化
        rst_n    = 1'b0  ;   
        data     = 32'd0 ;   
        send_en  = 1'b0  ;   
        Baud_Set = 3'd0  ;   
        #21 rst_n = 1'b1 ;
        // 数据发送: 0x12345678
        data = 32'h12345678 ;
        send_en = 1'b1 ;
        #20 ;
        send_en = 1'b0 ;
        #201 ;
        @(posedge Tx_Done); 

        // 数据发送: 0x87654321
        @(negedge clk);
        data    = 32'h87654321;
        send_en = 1'b1;

        @(negedge clk);
        send_en = 1'b0;
    end
endmodule
