// 串口发送测试
`timescale 1ns / 1ps
module uart_tx_test(
        input wire clk,
        input wire rst_n,

        output wire uart_tx,
        output wire LED
    );

    // 参数
    wire send_en ;  // 发送使能
    wire [7:0] data_byte ;  // 待传输的数据
    wire test_en ;  // 按键标志信号

    // 按键配置,使得send_en只能保持HIGH为1个周期
    reg test_en_dly1 ;
    reg test_en_dly2 ;

    always @(posedge clk) begin
        test_en_dly1 <= test_en ;
        test_en_dly2 <= test_en_dly1 ;
    end

    assign send_en = test_en_dly1 & !test_en_dly2;  // 意味着send_en只能持续1个周期的HIGH

    //----------- Begin Cut here for INSTANTIATION Template ---// INST_TAG
    vio_0 your_instance_name (
        .clk(clk),                // input wire clk
        .probe_out0(test_en),  // output wire [0 : 0] probe_out0
        .probe_out1(data_byte)  // output wire [7 : 0] probe_out1
    );

    // 实例uart_tx
    uart_byte_tx uart_byte_tx( 
        .clk(clk), 
        .rst_n(rst_n), 
        .data_byte(data_byte), 
        .send_en(send_en), 
        .baud_set(3'd0), 
        .uart_tx(uart_tx), 
        .tx_done(), 
        .uart_state(LED) 
    ); 
endmodule
