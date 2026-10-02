// 测试文件
// 使用说明：50MHz时钟，rst_n低电平复位；目标/编码器从0开始，初始电机停止。
// 按键1/2松开：目标位置加/减102计数（408计数/圈时约90度）；按键3松开返回复位原点。
// 按键3不清零编码器；按键4未使用。数码管左4位显示|PWM|，右4位显示|位置|末4位。
// 位置环20ms更新，PWM为20kHz、范围-2500~2500；正方向沿用3445a1d提交的接线配置。
// UART 115200/8N1：Protocol V1调节Kp/Ki/Kd（ID 10/11/12，Q16.16），复位恢复INIT参数。
// Telemetry每20ms上传goal(ID01)/real(ID02)/error(ID03)/set(ID04)，以及Kp/Ki/Kd。
// goal/real单位为编码器计数，set为带方向的PWM计数；调参后清积分，下个控制周期使用新参数。
// ADC接口保留以兼容现有XDC，本测试关闭ADC片选；I_LIMIT为积分项贡献的限幅值。
`timescale 1ns / 1ps
module Test #(
    parameter integer ENCODER_DIR_REVERSE = 0,
    parameter signed [31:0] KP_INIT = 32'sd1623462,
    parameter signed [31:0] KI_INIT = 32'sd0,
    parameter signed [31:0] KD_INIT = 32'sd1341560,
    parameter signed [31:0] I_LIMIT = 32'sd500
)(
    input wire clk,
    input wire rst_n,
    input wire [3:0] key_in,
    input wire encoder_a,
    input wire encoder_b,
    input wire uart_rx,
    output wire uart_tx,
    input wire ADC_DOUT,
    output wire ADC_SCLK,
    output wire ADC_DIN,
    output wire ADC_CS_N,
    output wire tb_in1,
    output wire tb_in2,
    output wire tb_pwm,
    output wire ds,
    output wire sh_cp,
    output wire st_cp
    );
    reg signed [31:0] target_position;
    reg [19:0] control_counter;
    wire pid_tick = (control_counter == 20'd999999);
    wire [2:0] key_release;
    wire signed [31:0] position_cnt;
    wire signed [31:0] kp, ki, kd;
    wire signed [31:0] pid_out;
    wire signed [32:0] pid_error;
    wire pid_valid;
    wire signed [31:0] goal = target_position;
    wire signed [31:0] real_position = position_cnt;
    wire signed [31:0] set = pid_out;
    wire signed [15:0] PWM = $signed(pid_out[15:0]);
    wire [15:0] pwm_abs = PWM[15] ? -PWM : PWM;
    wire [31:0] count_abs = position_cnt[31] ? -position_cnt : position_cnt;
    wire [31:0] Data = pwm_abs * 32'd10000 + count_abs % 32'd10000;
    wire set_valid, parameter_update;
    wire [7:0] set_param_id, set_param_type;
    wire [31:0] set_param_value;
    wire tx_busy;
    wire [7:0] param_index, param_count, param_id, param_type;
    wire [31:0] param_value;
    reg send_en;
    reg signed [31:0] sample_goal, sample_real, sample_kp, sample_ki, sample_kd;
    reg signed [31:0] frame_goal, frame_real, frame_error, frame_set;
    reg signed [31:0] frame_kp, frame_ki, frame_kd;

    assign ADC_SCLK = 1'b0;
    assign ADC_DIN = 1'b0;
    assign ADC_CS_N = 1'b1;

    genvar i;
    generate
        for (i = 0; i < 3; i = i + 1) begin : gen_keys
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
        end
    endgenerate

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            target_position <= 32'sd0;
            control_counter <= 20'd0;
        end else begin
            control_counter <= pid_tick ? 20'd0 : control_counter + 20'd1;
            if (key_release[2])
                target_position <= 32'sd0;
            else begin
                case (key_release[1:0])
                    2'b01: target_position <= target_position + 32'sd102;
                    2'b10: target_position <= target_position - 32'sd102;
                    default: ;
                endcase
            end
        end
    end

    protocol_rx
        protocol_rx_inst (
            .clk(clk),
            .rst_n(rst_n),
            .uart_rx(uart_rx),
            .baud_set(3'd4),
            .set_valid(set_valid),
            .set_param_id(set_param_id),
            .set_param_type(set_param_type),
            .set_param_value(set_param_value),
            .crc_error(),
            .format_error(),
            .last_seq()
        );

    parameter_manager #(.KP_INIT(KP_INIT), .KI_INIT(KI_INIT), .KD_INIT(KD_INIT))
        parameter_manager_inst (
            .clk(clk),
            .rst_n(rst_n),
            .set_valid(set_valid),
            .set_param_id(set_param_id),
            .set_param_type(set_param_type),
            .set_param_value(set_param_value),
            .kp(kp),
            .ki(ki),
            .kd(kd),
            .update_done(parameter_update),
            .type_error(),
            .id_error()
        );

    PID_Core
        PID_Core_inst (
            .clk(clk),
            .rst_n(rst_n),
            .pid_en(1'b1),
            .pid_clear(parameter_update),
            .pid_tick(pid_tick),
            .target(goal),
            .feedback(real_position),
            .kp_q(kp),
            .ki_q(ki),
            .kd_q(kd),
            .out_max(32'sd2500),
            .out_min(-32'sd2500),
            .i_limit(I_LIMIT),
            .pid_out(pid_out),
            .error_out(pid_error),
            .p_out(),
            .i_out(),
            .d_out(),
            .pid_valid(pid_valid)
        );

    // 先记录PID输入，再锁存整帧；发送期间保持所有字段不变，避免波形与系数混帧。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sample_goal <= 0; sample_real <= 0;
            sample_kp <= KP_INIT; sample_ki <= KI_INIT; sample_kd <= KD_INIT;
            frame_goal <= 0; frame_real <= 0; frame_error <= 0; frame_set <= 0;
            frame_kp <= KP_INIT; frame_ki <= KI_INIT; frame_kd <= KD_INIT;
            send_en <= 1'b0;
        end else begin
            send_en <= 1'b0;
            if (pid_tick && !parameter_update) begin
                sample_goal <= goal; sample_real <= real_position;
                sample_kp <= kp; sample_ki <= ki; sample_kd <= kd;
            end
            if (pid_valid && !tx_busy && !send_en) begin
                frame_goal <= sample_goal; frame_real <= sample_real;
                // 33位误差饱和成Protocol V1的INT32，避免极端位置相减翻转符号。
                frame_error <= (pid_error > 33'sd2147483647) ? 32'sh7fffffff :
                               (pid_error < -33'sd2147483648) ? 32'sh80000000 : pid_error[31:0];
                frame_set <= set;
                frame_kp <= sample_kp; frame_ki <= sample_ki; frame_kd <= sample_kd;
                send_en <= 1'b1;
            end
        end
    end

    telemetry_param_mux
        telemetry_param_mux_inst (
            .param_index(param_index),
            .target_position(frame_goal),
            .position(frame_real),
            .error(frame_error),
            .pid_output(frame_set),
            .kp(frame_kp),
            .ki(frame_ki),
            .kd(frame_kd),
            .param_count(param_count),
            .param_id(param_id),
            .param_type(param_type),
            .param_value(param_value)
        );

    protocol_tx
        protocol_tx_inst (
            .clk(clk),
            .rst_n(rst_n),
            .send_en(send_en),
            .baud_set(3'd4),
            .param_count(param_count),
            .param_index(param_index),
            .param_id(param_id),
            .param_type(param_type),
            .param_value(param_value),
            .uart_tx(uart_tx),
            .tx_busy(tx_busy),
            .tx_done()
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
            .format(2'd1),
            .ds(ds),
            .sh_cp(sh_cp),
            .st_cp(st_cp)
        );
endmodule
