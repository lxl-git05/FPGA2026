`timescale 1ns / 1ps
module uart_rx_test(
        input wire clk, 
        input wire rst_n, 
        input wire uart_rx 
    );

    wire rx_done ;
    reg [7:0] data_byte_reg; 
    wire [7:0] data_byte_rx ;

    uart_byte_rx  uart_byte_rx_inst (
        .clk(clk),
        .rst_n(rst_n),
        .baud_set(3'd0),
        .uart_rx(uart_rx),
        .rx_done(rx_done),
        .data_byte(data_byte_rx)
    );

    // 使用data_byte_reg <= data_byte_rx监视串口RX的值是否正确
    //----------- Begin Cut here for INSTANTIATION Template ---// INST_TAG
    vio_0 your_instance_name (
        .clk(clk),              // input wire clk
        .probe_in0(data_byte_reg)  // input wire [7 : 0] probe_in0
    );

    always@(posedge clk or negedge rst_n) 
    if(!rst_n)
        data_byte_reg <= 8'd0; 
    else if(rx_done) 
        data_byte_reg <= data_byte_rx; 
    else 
        data_byte_reg <= data_byte_reg; 

endmodule
