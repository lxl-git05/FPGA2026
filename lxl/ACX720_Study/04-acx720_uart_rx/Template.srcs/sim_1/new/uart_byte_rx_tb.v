`timescale 1ns / 1ps
module uart_byte_rx_tb;

    // 1. 例化RX
    //Ports
    reg  clk;
    reg  rst_n;
    reg [2:0] baud_set;
    wire  uart_tx_rx;
    wire rx_done;
    wire [7:0] data_byte_rx;

    uart_byte_rx  uart_byte_rx_inst (
        .clk(clk),
        .rst_n(rst_n),
        .baud_set(baud_set),
        .uart_rx(uart_tx_rx),
        .rx_done(rx_done),
        .data_byte(data_byte_rx)
    );

    // 2. 例化TX
    //Ports
    reg [7:0] data_byte_tx;
    reg  send_en;
    wire  tx_done;
    wire  uart_state;

    uart_byte_tx  uart_byte_tx_inst (
        .clk(clk),
        .rst_n(rst_n),
        .baud_set(baud_set),
        .data_byte(data_byte_tx),
        .send_en(send_en),
        .uart_tx(uart_tx_rx),
        .tx_done(tx_done),
        .uart_state(uart_state)
    );

    // 3. 逻辑
    // 3.1 时钟
    initial begin
        clk = 1'b0;
        forever 
            #10 clk = ~clk;
    end

    // 3.2 串口发送
    initial begin
        // 初始值
        rst_n     = 1'b0;
        baud_set  = 3'd0;
        data_byte_tx = 8'h00;
        send_en   = 1'b0;
        // 保持复位一段时间
        #100;
        rst_n = 1'b1;
        // 复位释放后等待
        #100;
        //==========================
        // 第一次发送：0x55
        //==========================
        data_byte_tx = 8'h55;

        // send_en尖峰触发TX
        send_en = 1'b1;
        #20;
        send_en = 1'b0;

        // 等待发送完成
        wait(tx_done == 1'b1);

        // 再等待一点时间
        #200;

        //==========================
        // 第二次发送：0xA5
        //==========================
        data_byte_tx = 8'hA5;

        // send_en尖峰触发TX
        send_en = 1'b1;
        #20;
        send_en = 1'b0;

        wait(tx_done == 1'b1);

        #200;

        //==========================
        // 第三次发送：0x31
        // ASCII '1'
        //==========================
        data_byte_tx = 8'h31;

        // send_en尖峰触发TX
        send_en = 1'b1;
        #20;
        send_en = 1'b0;

        wait(tx_done == 1'b1);

        #500;

        $stop;
    end

endmodule
