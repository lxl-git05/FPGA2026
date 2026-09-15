// 项目: 串口发送单个字符(Byte)
`timescale 1ns / 1ps
module uart_byte_tx(
        input wire clk,
        input wire rst_n,

        input wire [2:0] baud_set,      // 波特率选择
        input wire [7:0] data_byte,     // 需要Tx的信息
        input wire send_en,             // 串口使能信号

        output wire uart_tx,             // 串口输出口
        output wire tx_done,             // 输出完成信号
        output wire uart_state           // TX端口状态
    );

    // 进行例化
    // 1. 串口选择
    wire [15:0] bps_DR ;
    DR_LUT  DR_LUT_inst (
        .clk(clk),
        .rst_n(rst_n),
        .baud_set(baud_set),
        .bps_DR(bps_DR)
    );
    // 2. 波特率时钟输出
    wire bps_clk ;
    div_cnt  div_cnt_inst (
        .clk(clk),
        .rst_n(rst_n),
        .uart_state(uart_state),
        .bps_DR(bps_DR),
        .bps_clk(bps_clk)
    );
    // 3. 波特率周期计数
    wire [3:0] bps_cnt ;
    bps_cnt  bps_cnt_inst (
        .clk(clk),
        .rst_n(rst_n),
        .bps_clk(bps_clk),
        .bps_cnt(bps_cnt)
    );
    // 4. 输出完成标志位
    tx_done_reg  tx_done_reg_inst (
        .clk(clk),
        .rst_n(rst_n),
        .bps_cnt(bps_cnt),
        .tx_done(tx_done)
    );
    // 5. 串口TX状态标志位
    uart_state_reg  uart_state_reg_inst (
        .clk(clk),
        .rst_n(rst_n),
        .bps_cnt(bps_cnt),
        .send_en(send_en),
        .uart_state(uart_state)
    );
    // 6. TX数据锁存器
    wire [7:0] data_byte_reg ;
    data_reg  data_reg_inst (
        .clk(clk),
        .rst_n(rst_n),
        .send_en(send_en),
        .data_byte(data_byte),
        .data_byte_reg(data_byte_reg)
    );
    // 7. 串口输出端口
    mux_tx # 
    (
        .START_BIT(0),
        .STOP_BIT(1)
    )
    mux_tx_inst (
        .clk(clk),
        .rst_n(rst_n),
        .bps_cnt(bps_cnt),
        .data_byte_reg(data_byte_reg),
        .uart_tx(uart_tx)
    );
endmodule
