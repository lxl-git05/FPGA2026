// 测试文件
// 使用说明：50MHz时钟，rst_n低电平复位；复位后PWM和编码器计数为0，电机停止。
// 按键1/2（key_in[0]/[1]）松开：目标位置加/减102计数（每圈408，约90度）。
// 按键3（key_in[2]）松开：目标设为0，返回复位原点，不清零编码器。
// 顺时针为PWM和编码器的正方向；方向已固定，按键4暂不使用。
// 位置PD每20ms更新；PWM限幅±2500（100%），PWM频率20kHz。
// 数码管左四位显示|PWM|，右四位显示|编码器四倍频累计计数|的末四位，均为十进制。
// 当前接线：电机DIR_REVERSE=1，ENCODER_DIR_REVERSE=0，顺时针计数增加。
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
    // Mode4换算：角度->计数，PWM±100->±2500，Kd计入20ms采样周期。
    localparam signed [31:0] KP_Q = 32'sd1623462, KD_Q = 32'sd1341560;
    reg signed [31:0] target_position;
    reg [19:0] control_counter;
    wire pid_tick = (control_counter == 20'd999999);
    wire signed [31:0] pid_out;
    wire signed [15:0] PWM = $signed(pid_out[15:0]);
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

    // 50MHz下1000000拍为20ms；目标累计，不对一圈取模。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            target_position <= 32'sd0;
            control_counter <= 20'd0;
        end else begin
            control_counter <= pid_tick ? 20'd0 : control_counter + 1'b1;
            if (key_release[2]) target_position <= 32'sd0;
            else case (key_release[1:0])
                2'b01: target_position <= target_position + 32'sd102;
                2'b10: target_position <= target_position - 32'sd102;
                default: ; // 同时松开按键1、2时保持目标
            endcase
        end
    end

    PID_Core
        PID_Core_inst (
            .clk(clk),
            .rst_n(rst_n),
            .pid_en(1'b1),
            .pid_clear(1'b0),
            .pid_tick(pid_tick),
            .target(target_position),
            .feedback(position_cnt),
            .kp_q(KP_Q),
            .ki_q(32'sd0),
            .kd_q(KD_Q),
            .out_max(32'sd2500),
            .out_min(-32'sd2500),
            .i_limit(32'sd0),
            .pid_out(pid_out),
            .error_out(),
            .p_out(),
            .i_out(),
            .d_out(),
            .pid_valid()
        );

    TB6612_Motor_driver #(.DIR_REVERSE(1))
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
