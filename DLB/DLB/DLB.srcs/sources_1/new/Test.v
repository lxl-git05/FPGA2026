// 测试文件
// 使用说明：50MHz时钟，rst_n低电平复位；释放复位后连续采样板载ADC的IN0。
// 无按键操作；数码管显示ADC原始值0~4095，十进制右对齐、高位留空，复位显示0。
// ADC_CHANNEL可选0~7；ADC_SCLK_DIV默认2，对应12.5MHz串行时钟。
// 模拟信号接所选IN通道并共地；ADC_DOUT为FPGA输入，其余三个ADC接口为输出。
`timescale 1ns / 1ps
module Test #(
    parameter [2:0] ADC_CHANNEL = 3'd0,
    parameter integer ADC_SCLK_DIV = 2
)(
    input wire clk,
    input wire rst_n,
    input wire  ADC_DOUT,
    output wire ADC_SCLK,
    output wire ADC_DIN ,
    output wire ADC_CS_N,
    output wire ds,
    output wire sh_cp,
    output wire st_cp

    );
    wire [11:0] adc_data;

    adc128s102 #(.CHANNEL(ADC_CHANNEL), .SCLK_DIV(ADC_SCLK_DIV))
        adc128s102_inst (
            .clk(clk),
            .rst_n(rst_n),
            .ADC_DOUT(ADC_DOUT),
            .ADC_SCLK(ADC_SCLK),
            .ADC_DIN(ADC_DIN),
            .ADC_CS_N(ADC_CS_N),
            .data(adc_data),
            .data_valid() // 驱动保持最近结果，数码管直接读取
        );

    Seg8 #(.DECIMAL_SPLIT(0))
        Seg8_inst (
            .clk(clk),
            .reset_n(rst_n),
            .data({20'd0, adc_data}),
            .format(2'd1), // 固定十进制显示
            .ds(ds),
            .sh_cp(sh_cp),
            .st_cp(st_cp)
        );
endmodule
