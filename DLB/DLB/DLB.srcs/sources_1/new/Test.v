// 测试文件
// 使用说明：50MHz时钟，rst_n低电平复位；复位后PWM和编码器计数为0，电机停止。
// 按键1/2（key_in[0]/[1]）松开：PWM加/减250，范围-2500～2500。
// 按键3（key_in[2]）松开：PWM取反换向；PWM为0时仍停止，按键4未使用。
// PWM正值正转、负值反转；PWM幅值2500为100%占空比，PWM频率20kHz。
// 数码管左四位显示|PWM|，右四位显示|编码器四倍频累计计数|的末四位，均为十进制。
// ENCODER_DIR_REVERSE=0保持原编码器方向，=1反向；按实际顺/逆时针计数结果选择。
`timescale 1ns / 1ps
module Test #(
    parameter integer ENCODER_DIR_REVERSE = 0
)(
    input wire clk,
    input wire rst_n,
    input wire [3:0] key_in,
    input wire encoder_a,
    input wire encoder_b,
    output wire tb_in1,
    output wire tb_in2,
    output wire tb_pwm,
    output wire ds,
    output wire sh_cp,
    output wire st_cp

    );
    reg signed [15:0] PWM;
    wire [2:0] key_release;
    wire signed [31:0] position_cnt;
    wire [15:0] pwm_abs = PWM[15] ? -PWM : PWM;
    wire [31:0] count_abs = position_cnt[31] ? -position_cnt : position_cnt;
    // 左四位PWM，右四位编码器计数；超出四位的计数保留末四位。
    wire [31:0] Data = pwm_abs * 32'd10000 + count_abs % 32'd10000;

    genvar i;
    generate for (i = 0; i < 3; i = i + 1) begin : keys
        key
            key_inst (
                .clk(clk),
                .rst_n(rst_n),
                .key_in(key_in[i]),
                .key_state(),
                .key_press(),
                .key_release(key_release[i]),
                .key_change()
            );
    end endgenerate

    // PWM符号决定方向，幅值限2500；按键3取反换向，零值保持停止。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            PWM <= 16'sd0;
        end else begin
            if (key_release[2]) PWM <= -PWM;
            else case (key_release[1:0])
                2'b01: if (PWM < 16'sd2500) PWM <= PWM + 16'sd250;
                2'b10: if (PWM > -16'sd2500) PWM <= PWM - 16'sd250;
                default: ; // 同时松开按键1、2时保持PWM
            endcase
        end
    end

    TB6612_Motor_driver
        TB6612_Motor_driver_inst (
            .clk(clk),
            .rst_n(rst_n),
            .motor_en(1'b1),
            .motor_brake(1'b0),
            .motor_pwm(PWM),
            .tb_in1(tb_in1),
            .tb_in2(tb_in2),
            .tb_pwm(tb_pwm)
        );

    // 编码器正方向由参数配置，系统复位时清零。
    encoder_quad #(.DIR_REVERSE(ENCODER_DIR_REVERSE))
        encoder_quad_inst (
            .clk(clk),
            .rst_n(rst_n),
            .encoder_a(encoder_a),
            .encoder_b(encoder_b),
            .position_zero(1'b0),
            .position_cnt(position_cnt)
        );

    Seg8 #(.DECIMAL_SPLIT(1))
        Seg8_inst (
            .clk(clk),
            .reset_n(rst_n),
            .data(Data),
            .format(2'd1), // 固定十进制显示
            .ds(ds),
            .sh_cp(sh_cp),
            .st_cp(st_cp)
        );
endmodule
