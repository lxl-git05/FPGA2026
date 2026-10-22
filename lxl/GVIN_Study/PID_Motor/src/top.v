// PID_Motor：J280/XH1单环位置PID，50MHz，SW5低有效复位；上电立即保持复位零位。
// 模块：本工程PID_Core采用分拍运算；原encoder_quad、电机/PWM、uart_byte_rx/tx保持不变。
// 业务：20ms控制，1040计数/圈；顺时针为正，电机/编码器反向参数均为1；电机使用B桥。
// RX 115200/8N1 ASCII：@Kp=0.80$# @Ki=0.51$# @Kd=0.49$# @goal_A=78$#。
// 参数按C公式：Kp=0.98/Ki=0/Kd=0.12，顶层折算dt、度/计数、百分比/PWM计数。
// 数值支持正负及最多6位小数；每帧含@/$#不超过32字节；残帧100ms超时，新@重新同步。
// 完整$#才提交，命令外CR/LF忽略；错误/越界整帧拒收，无ACK。换系数清PID，改目标保留历史。
// TX每次PID完成上传goal,real,set：请求目标度/同次反馈度/输出百分比，各6位小数及显式CR/LF。
// 发送期间冻结三字段；串口与控制并行；目标取最近编码器计数，输出±2500，I项贡献±500。
// 目标和系数同拍控制边界到达时，下个周期生效；无额外按键、ADC、显示或串口启停业务。
`timescale 1ns / 1ps
module top #(
    parameter integer COUNTS_PER_REV = 1040,
    parameter integer CONTROL_MS = 20,
    parameter integer MOTOR_DIR_REVERSE = 1,
    parameter integer ENCODER_DIR_REVERSE = 1
)(
    input wire clk,
    input wire rst_n,
    input wire encoder_a,
    input wire encoder_b,
    input wire uart_rx,
    output wire uart_tx,
    output wire tb_in1,
    output wire tb_in2,
    output wire tb_pwm
);
    localparam integer CONTROL_TICKS = 50000 * CONTROL_MS;
    localparam integer TIMER_WIDTH = (CONTROL_TICKS > 1) ? $clog2(CONTROL_TICKS) : 1;
    localparam [63:0] P_NUM = 64'd589824000;
    localparam [63:0] I_NUM = P_NUM * CONTROL_MS;
    localparam [63:0] D_NUM = P_NUM * 1000;
    localparam [63:0] P_DEN = 64'd1000000 * COUNTS_PER_REV;
    localparam [63:0] I_DEN = 64'd1000000000 * COUNTS_PER_REV;
    localparam [63:0] D_DEN = P_DEN * CONTROL_MS;
    localparam [127:0] P_INIT_WIDE = (128'd980000 * P_NUM + P_DEN/2) / P_DEN;
    localparam [127:0] D_INIT_WIDE = (128'd120000 * D_NUM + D_DEN/2) / D_DEN;
    localparam [1:0] PARAM_KP = 0, PARAM_KI = 1, PARAM_KD = 2, PARAM_GOAL = 3;

    wire [7:0] rx_data;
    wire rx_done, tx_done;
    reg [7:0] tx_data;
    reg tx_send;
    wire signed [31:0] position_cnt, pid_out;
    wire pid_valid;
    reg signed [31:0] config_kp, config_ki, config_kd, config_target;
    reg signed [63:0] config_goal_micro;
    reg [31:0] gain_epoch, applied_epoch;

    uart_byte_rx
        uart_byte_rx_inst (
            .clk(clk),
            .rst_n(rst_n),
            .baud_set(3'd4),
            .uart_rx(uart_rx),
            .data_byte(rx_data),
            .rx_Done(rx_done)
        );
    uart_byte_tx
        uart_byte_tx_inst (
            .clk(clk),
            .rst_n(rst_n),
            .data_byte(tx_data),
            .send_en(tx_send),
            .baud_set(3'd4),
            .uart_tx(uart_tx),
            .tx_done(tx_done),
            .uart_state()
        );
    encoder_quad #(.DIR_REVERSE(ENCODER_DIR_REVERSE))
        encoder_inst (
            .clk(clk),
            .rst_n(rst_n),
            .encoder_a(encoder_a),
            .encoder_b(encoder_b),
            .position_zero(1'b0),
            .position_cnt(position_cnt)
        );

    // RX：语法状态与多周期单位换算。先归一化为百万分之一，再作有理数换算。
    localparam [3:0] R_IDLE=0, R_NAME=1, R_NUMBER=2, R_HASH=3,
                     R_SCALE=4, R_SCALE_MUL=5, R_SCALE_CHECK=6,
                     R_GAIN_MUL=7, R_DIV_SETUP=8, R_DIV=9, R_COMMIT=10;
    reg [3:0] rx_state;
    reg [5:0] frame_length;
    reg [47:0] name_shift;
    reg [2:0] name_length, frac_digits;
    reg [1:0] param_kind;
    reg number_started, number_negative, number_dot, number_has_digit;
    reg [63:0] number_mantissa, micro_magnitude;
    reg [22:0] rx_age;
    wire rx_receiving = (rx_state == R_NAME) || (rx_state == R_NUMBER) || (rx_state == R_HASH);
    wire rx_timeout = rx_receiving && (rx_age == 23'd4999999);
    wire rx_digit_valid = (rx_data >= "0") && (rx_data <= "9");
    wire [3:0] rx_digit = rx_data[3:0];
    wire mantissa_overflow = (number_mantissa > 64'd1844674407370955161) ||
                             ((number_mantissa == 64'd1844674407370955161) && (rx_digit > 5));
    function [63:0] decimal_scale;
        input [2:0] fractional;
        begin
            case (fractional)
                0: decimal_scale=1000000;
                1: decimal_scale=100000;
                2: decimal_scale=10000;
                3: decimal_scale=1000;
                4: decimal_scale=100;
                5: decimal_scale=10;
                default: decimal_scale=1;
            endcase
        end
    endfunction
    wire [63:0] gain_multiplier = (param_kind == PARAM_KP) ? P_NUM :
                                  (param_kind == PARAM_KI) ? I_NUM :
                                  (param_kind == PARAM_KD) ? D_NUM : COUNTS_PER_REV;
    wire [63:0] gain_divisor = (param_kind == PARAM_KP) ? P_DEN :
                               (param_kind == PARAM_KI) ? I_DEN :
                               (param_kind == PARAM_KD) ? D_DEN : 64'd360000000;
    reg [127:0] multiply_acc, multiply_a, multiply_result;
    reg [63:0] multiply_b;
    reg [6:0] multiply_count;
    wire [127:0] multiply_next = multiply_acc + (multiply_b[0] ? multiply_a : 128'd0);
    reg [127:0] command_dividend, command_quotient;
    reg [63:0] command_remainder, command_divisor;
    reg [6:0] divide_count;
    wire [64:0] command_trial = {command_remainder, command_dividend[127]};
    wire [65:0] command_subtract = {1'b0, command_trial} - {2'b0, command_divisor};
    wire command_range_ok = number_negative ? (command_quotient <= 128'd2147483648) :
                                               (command_quotient <= 128'd2147483647);
    wire signed [31:0] command_signed = number_negative ? -$signed(command_quotient[31:0]) :
                                                                         $signed(command_quotient[31:0]);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) rx_age <= 0;
        else if (!rx_receiving || rx_done) rx_age <= 0;
        else if (!rx_timeout) rx_age <= rx_age + 1'b1;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_state <= R_IDLE; frame_length <= 0; name_shift <= 0; name_length <= 0;
            frac_digits <= 0; param_kind <= 0; number_started <= 0;
            number_negative <= 0; number_dot <= 0; number_has_digit <= 0;
            number_mantissa <= 0; micro_magnitude <= 0;
            multiply_acc <= 0; multiply_a <= 0; multiply_b <= 0;
            multiply_result <= 0; multiply_count <= 0;
            command_dividend <= 0; command_quotient <= 0; command_remainder <= 0;
            command_divisor <= 1; divide_count <= 0;
            config_kp <= P_INIT_WIDE[31:0]; config_ki <= 0; config_kd <= D_INIT_WIDE[31:0];
            config_target <= 0; config_goal_micro <= 0; gain_epoch <= 0;
        end else if (rx_done && (rx_data == "@")) begin
            rx_state <= R_NAME; frame_length <= 1; name_shift <= 0; name_length <= 0;
            frac_digits <= 0; number_started <= 0; number_negative <= 0;
            number_dot <= 0; number_has_digit <= 0; number_mantissa <= 0;
        end else if (rx_done && rx_receiving) begin
            if (frame_length == 32) rx_state <= R_IDLE;
            else begin
                frame_length <= frame_length + 1'b1;
                case (rx_state)
                    R_NAME: begin
                        if (rx_data == "=") begin
                            if ((name_length == 2) && (name_shift == "Kp")) begin param_kind <= PARAM_KP; rx_state <= R_NUMBER; end
                            else if ((name_length == 2) && (name_shift == "Ki")) begin param_kind <= PARAM_KI; rx_state <= R_NUMBER; end
                            else if ((name_length == 2) && (name_shift == "Kd")) begin param_kind <= PARAM_KD; rx_state <= R_NUMBER; end
                            else if ((name_length == 6) && (name_shift == "goal_A")) begin param_kind <= PARAM_GOAL; rx_state <= R_NUMBER; end
                            else rx_state <= R_IDLE;
                        end else if (name_length < 6) begin
                            name_shift <= {name_shift[39:0], rx_data};
                            name_length <= name_length + 1'b1;
                        end else rx_state <= R_IDLE;
                    end
                    R_NUMBER: begin
                        if (!number_started && ((rx_data == "+") || (rx_data == "-"))) begin
                            number_started <= 1;
                            number_negative <= (rx_data == "-");
                        end else if (rx_digit_valid) begin
                            if (mantissa_overflow || (number_dot && frac_digits == 6)) rx_state <= R_IDLE;
                            else begin
                                number_mantissa <= number_mantissa * 64'd10 + {60'b0, rx_digit};
                                number_started <= 1; number_has_digit <= 1;
                                if (number_dot) frac_digits <= frac_digits + 1'b1;
                            end
                        end else if ((rx_data == ".") && !number_dot) begin
                            number_dot <= 1; number_started <= 1;
                        end else if ((rx_data == "$") && number_has_digit) rx_state <= R_HASH;
                        else rx_state <= R_IDLE;
                    end
                    R_HASH: rx_state <= (rx_data == "#") ? R_SCALE : R_IDLE;
                    default: rx_state <= R_IDLE;
                endcase
            end
        end else if (rx_timeout) rx_state <= R_IDLE;
        else begin
            case (rx_state)
                R_SCALE: begin
                    multiply_acc <= 0; multiply_a <= {64'b0, number_mantissa};
                    multiply_b <= decimal_scale(frac_digits); multiply_count <= 19;
                    rx_state <= R_SCALE_MUL;
                end
                R_SCALE_MUL, R_GAIN_MUL: begin
                    multiply_acc <= multiply_next;
                    multiply_a <= multiply_a << 1;
                    multiply_b <= multiply_b >> 1;
                    if (multiply_count == 0) begin
                        multiply_result <= multiply_next;
                        rx_state <= (rx_state == R_SCALE_MUL) ? R_SCALE_CHECK : R_DIV_SETUP;
                    end else multiply_count <= multiply_count - 1'b1;
                end
                R_SCALE_CHECK: begin
                    if (multiply_result[127:64] != 0) rx_state <= R_IDLE;
                    else begin
                        micro_magnitude <= multiply_result[63:0];
                        multiply_acc <= 0; multiply_a <= multiply_result;
                        multiply_b <= gain_multiplier; multiply_count <= 63;
                        rx_state <= R_GAIN_MUL;
                    end
                end
                R_DIV_SETUP: begin
                    // 幅值加半分母后作整数除法，最后恢复符号，实现正负对称舍入。
                    command_dividend <= multiply_result + {64'b0, (gain_divisor >> 1)};
                    command_divisor <= gain_divisor;
                    command_quotient <= 0; command_remainder <= 0; divide_count <= 127;
                    rx_state <= R_DIV;
                end
                R_DIV: begin
                    command_dividend <= command_dividend << 1;
                    if (!command_subtract[65]) begin
                        command_remainder <= command_subtract[63:0];
                        command_quotient <= {command_quotient[126:0], 1'b1};
                    end else begin
                        command_remainder <= command_trial[63:0];
                        command_quotient <= {command_quotient[126:0], 1'b0};
                    end
                    if (divide_count == 0) rx_state <= R_COMMIT;
                    else divide_count <= divide_count - 1'b1;
                end
                R_COMMIT: begin
                    if (command_range_ok) begin
                        case (param_kind)
                            PARAM_KP: begin config_kp <= command_signed; gain_epoch <= gain_epoch + 1'b1; end
                            PARAM_KI: begin config_ki <= command_signed; gain_epoch <= gain_epoch + 1'b1; end
                            PARAM_KD: begin config_kd <= command_signed; gain_epoch <= gain_epoch + 1'b1; end
                            PARAM_GOAL: begin
                                config_target <= command_signed;
                                config_goal_micro <= number_negative ? -$signed(micro_magnitude) : $signed(micro_magnitude);
                            end
                        endcase
                    end
                    rx_state <= R_IDLE;
                end
                default: ;
            endcase
        end
    end

    reg [TIMER_WIDTH-1:0] control_count;
    wire control_due = (control_count == CONTROL_TICKS - 1);
    reg signed [31:0] sample_target, sample_position, sample_kp, sample_ki, sample_kd;
    reg signed [63:0] sample_goal_micro;
    reg pid_tick, pid_clear, clear_pending;
    // 周期边界配置读旧值，恰同拍提交的新配置自然延后到下一周期。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            control_count <= 0; sample_target <= 0; sample_position <= 0; sample_goal_micro <= 0;
            sample_kp <= P_INIT_WIDE[31:0]; sample_ki <= 0; sample_kd <= D_INIT_WIDE[31:0];
            applied_epoch <= 0; pid_tick <= 0; pid_clear <= 0; clear_pending <= 0;
        end else begin
            if (control_due) control_count <= 0;
            else control_count <= control_count + 1'b1;
            pid_tick <= 0; pid_clear <= 0;
            if (clear_pending) begin
                pid_tick <= 1; clear_pending <= 0;
            end
            if (control_due) begin
                sample_target <= config_target; sample_position <= position_cnt;
                sample_goal_micro <= config_goal_micro;
                sample_kp <= config_kp; sample_ki <= config_ki; sample_kd <= config_kd;
                if (applied_epoch != gain_epoch) begin
                    pid_clear <= 1; clear_pending <= 1; applied_epoch <= gain_epoch;
                end else pid_tick <= 1;
            end
        end
    end
    PID_Core
        pid_inst (
            .clk(clk),
            .rst_n(rst_n),
            .pid_en(rst_n),
            .pid_clear(pid_clear),
            .pid_tick(pid_tick),
            .target(sample_target),
            .feedback(sample_position),
            .kp_q(sample_kp),
            .ki_q(sample_ki),
            .kd_q(sample_kd),
            .out_max(32'sd2000),
            .out_min(-32'sd2000),
            .i_limit(32'sd500),
            .pid_out(pid_out),
            .error_out(),
            .p_out(),
            .i_out(),
            .d_out(),
            .pid_valid(pid_valid)
        );
    TB6612_Motor_driver #(.DIR_REVERSE(MOTOR_DIR_REVERSE))
        motor_inst (
            .clk(clk),
            .rst_n(rst_n),
            .motor_en(rst_n),
            .motor_brake(1'b0),
            .motor_pwm(pid_out[15:0]),
            .tb_in1(tb_in1),
            .tb_in2(tb_in2),
            .tb_pwm(tb_pwm)
        );

    // TX：每次PID完成冻结同次采样，先换算百万分之一，再逐拍BCD转换与发送。
    localparam [3:0] F_IDLE=0, F_LOAD=1, F_REAL_DIV=2, F_BCD_LOAD=3, F_BCD=4,
                     F_SIGN=5, F_DIGIT=6, F_WAIT_DIGIT=7, F_DOT=8,
                     F_SEPARATOR=9, F_LF=10, F_WAIT_LF=11, F_WAIT_SIGN=12,
                     F_WAIT_DOT=13, F_WAIT_SEPARATOR=14;
    reg [3:0] format_state;
    reg signed [63:0] frame_goal_micro;
    reg signed [31:0] frame_position, frame_output;
    reg [1:0] field_index;
    reg field_negative;
    reg [63:0] field_micro, real_dividend, real_quotient, real_remainder;
    reg [5:0] format_count;
    wire [64:0] real_trial = {real_remainder, real_dividend[63]};
    wire [65:0] real_subtract = {1'b0, real_trial} - {34'b0, COUNTS_PER_REV[31:0]};
    wire [31:0] position_magnitude = frame_position[31] ? (~frame_position + 32'd1) : frame_position;
    wire [31:0] output_magnitude = frame_output[31] ? (~frame_output + 32'd1) : frame_output;
    reg [143:0] bcd_shift, bcd_adjusted;
    wire [143:0] bcd_next = bcd_adjusted << 1;
    reg [79:0] decimal_digits;
    reg [4:0] digit_index;
    reg digit_started, dot_sent;
    integer digit;
    always @(*) begin
        bcd_adjusted = bcd_shift;
        for (digit=0; digit<20; digit=digit+1)
            if (bcd_shift[64+digit*4 +: 4] >= 5)
                bcd_adjusted[64+digit*4 +: 4] = bcd_shift[64+digit*4 +: 4] + 4'd3;
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            format_state <= F_IDLE; frame_goal_micro <= 0; frame_position <= 0; frame_output <= 0;
            field_index <= 0; field_negative <= 0; field_micro <= 0;
            real_dividend <= 0; real_quotient <= 0; real_remainder <= 0; format_count <= 0;
            bcd_shift <= 0; decimal_digits <= 0; digit_index <= 0; digit_started <= 0;
            dot_sent <= 0; tx_data <= 0; tx_send <= 0;
        end else begin
            tx_send <= 0;
            case (format_state)
                F_IDLE: if (pid_valid) begin
                    frame_goal_micro <= sample_goal_micro; frame_position <= sample_position;
                    frame_output <= pid_out; field_index <= 0; format_state <= F_LOAD;
                end
                F_LOAD: begin
                    case (field_index)
                        0: begin
                            field_negative <= frame_goal_micro[63];
                            field_micro <= frame_goal_micro[63] ? (~frame_goal_micro + 64'd1) : frame_goal_micro;
                            format_state <= F_BCD_LOAD;
                        end
                        1: begin
                            field_negative <= frame_position[31];
                            real_dividend <= {32'b0, position_magnitude} * 64'd360000000 + COUNTS_PER_REV/2;
                            real_quotient <= 0; real_remainder <= 0; format_count <= 63;
                            format_state <= F_REAL_DIV;
                        end
                        default: begin
                            field_negative <= frame_output[31];
                            field_micro <= {32'b0, output_magnitude} * 64'd40000;
                            format_state <= F_BCD_LOAD;
                        end
                    endcase
                end
                F_REAL_DIV: begin
                    real_dividend <= real_dividend << 1;
                    if (!real_subtract[65]) begin
                        real_remainder <= real_subtract[63:0];
                        real_quotient <= {real_quotient[62:0], 1'b1};
                    end else begin
                        real_remainder <= real_trial[63:0];
                        real_quotient <= {real_quotient[62:0], 1'b0};
                    end
                    if (format_count == 0) begin
                        field_micro <= {real_quotient[62:0], !real_subtract[65]};
                        format_state <= F_BCD_LOAD;
                    end else format_count <= format_count - 1'b1;
                end
                F_BCD_LOAD: begin
                    bcd_shift <= {80'b0, field_micro}; format_count <= 63;
                    digit_index <= 0; digit_started <= 0; dot_sent <= 0;
                    format_state <= F_BCD;
                end
                F_BCD: begin
                    bcd_shift <= bcd_next;
                    if (format_count == 0) begin decimal_digits <= bcd_next[143:64]; format_state <= F_SIGN; end
                    else format_count <= format_count - 1'b1;
                end
                F_SIGN: begin
                    if (field_negative && (field_micro != 0)) begin
                        tx_data <= "-"; tx_send <= 1; format_state <= F_WAIT_SIGN;
                    end else format_state <= F_DIGIT;
                end
                F_WAIT_SIGN: if (tx_done) format_state <= F_DIGIT;
                F_DIGIT: begin
                    if ((digit_index == 14) && !dot_sent) format_state <= F_DOT;
                    else if (!digit_started && (digit_index < 13) && (decimal_digits[79:76] == 0)) begin
                        decimal_digits <= decimal_digits << 4; digit_index <= digit_index + 1'b1;
                    end else begin
                        tx_data <= 8'h30 + {4'b0, decimal_digits[79:76]};
                        tx_send <= 1; digit_started <= 1; format_state <= F_WAIT_DIGIT;
                    end
                end
                F_WAIT_DIGIT: if (tx_done) begin
                    if (digit_index == 19) format_state <= F_SEPARATOR;
                    else begin
                        decimal_digits <= decimal_digits << 4; digit_index <= digit_index + 1'b1;
                        format_state <= F_DIGIT;
                    end
                end
                F_DOT: begin tx_data <= "."; tx_send <= 1; dot_sent <= 1; format_state <= F_WAIT_DOT; end
                F_WAIT_DOT: if (tx_done) format_state <= F_DIGIT;
                F_SEPARATOR: begin
                    tx_data <= (field_index == 2) ? 8'h0d : 8'h2c;
                    tx_send <= 1; format_state <= F_WAIT_SEPARATOR;
                end
                F_WAIT_SEPARATOR: if (tx_done) begin
                    if (field_index == 2) format_state <= F_LF;
                    else begin field_index <= field_index + 1'b1; format_state <= F_LOAD; end
                end
                F_LF: begin tx_data <= 8'h0a; tx_send <= 1; format_state <= F_WAIT_LF; end
                F_WAIT_LF: if (tx_done) format_state <= F_IDLE;
                default: format_state <= F_IDLE;
            endcase
        end
    end
endmodule
