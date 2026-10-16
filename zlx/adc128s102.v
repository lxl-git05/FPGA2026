`timescale 1ns / 1ps
// 适配 3PA1030（10bit 并行 ADC），输出 3ms 平均角度。
// 端口沿用 adc128s102 的命名，仅 ADC_DOUT 扩为 10 位以承载并行数据。
// data_valid 仍为单周期脉冲，data 保持最近一次有效结果。
module adc128s102 #(
    parameter integer CLK_DIV = 1   // 50MHz / (2*CLK_DIV) = 25MHz
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [9:0]  ADC_DOUT,    // 3PA1030 D9~D0 并行数据
    output reg         ADC_SCLK,    // → adc_clk（25MHz 采样时钟）
    output reg         ADC_DIN,     // → adc_stby_n（1=工作）
    output reg         ADC_CS_N,    // → adc_oe_n  （0=输出使能）
    output reg  [11:0] data,
    output reg         data_valid
);
    reg        clk_div;
    reg [17:0] cnt_3ms;
    reg [13:0] cnt_187us;
    reg [15:0] theta_sum;

    // ---------- 1) 采样时钟：50MHz 二分频 -> 25MHz ----------
    always @(posedge clk or negedge rst_n)
        if (!rst_n) clk_div <= 1'b0;
        else        clk_div <= ~clk_div;

    always @(*) ADC_SCLK = clk_div;

    // ---------- 2) 静态控制信号 ----------
    // stby_n 高有效工作；oe_n 低有效使能输出
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ADC_DIN  <= 1'b0;
            ADC_CS_N <= 1'b1;
        end else begin
            ADC_DIN  <= 1'b1;   // adc_stby_n = 1，退出休眠
            ADC_CS_N <= 1'b0;   // adc_oe_n  = 0，输出使能
        end
    end

    // ---------- 3) 3ms 计数器（50MHz × 150000） ----------
    always @(posedge clk or negedge rst_n)
        if (!rst_n)                       cnt_3ms <= 16'd0;
        else if (cnt_3ms == 18'd149_999)  cnt_3ms <= 16'd0;
        else                              cnt_3ms <= cnt_3ms + 1'b1;

    // ---------- 4) 187.5us 计数器（50MHz × 9375） ----------
    always @(posedge clk or negedge rst_n)
        if (!rst_n)                       cnt_187us <= 14'd0;
        else if (cnt_187us == 14'd9374)   cnt_187us <= 14'd0;
        else                              cnt_187us <= cnt_187us + 1'b1;

    // ---------- 5) 每 187.5us 采一点，每 3ms 平均输出 ----------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            theta_sum  <= 16'd0;
            data       <= 12'd0;
            data_valid <= 1'b0;
        end else begin
            data_valid <= 1'b0;
            if (cnt_187us == 14'd9373) begin
                // 10bit 左移 2 位扩展为 12bit，再累加
                theta_sum <= theta_sum + {ADC_DOUT, 2'b0};
            end
            if (cnt_3ms == 18'd149_999) begin
                data       <= theta_sum[15:4];  // 右移 4 位 = /16
                data_valid <= 1'b1;             // 单周期脉冲
                theta_sum  <= 16'd0;
            end
        end
    end
endmodule