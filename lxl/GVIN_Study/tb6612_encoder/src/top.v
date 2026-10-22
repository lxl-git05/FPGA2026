// 工程：J280 XH1开环电机与编码器测试；按底板原理图电机接B桥，50MHz，SW5低有效复位。
// 模块：原TB6612_Motor_driver/pwm_gen/encoder_quad原样引用，复用uart_byte_rx/tx。
// 业务：115200/8N1接收有符号十进制PWM计数[-2500,+2500]；20kHz，1250=50%，20=0.8%。
// CR(0D)、LF(0A)或CRLF结束命令；无换行时末字节后空闲10ms提交；空行忽略。
// 格式为可选+/-及1~4位数字；非法字符、符号无数字、越界整条丢弃，保持上一PWM。
// 串口工具选文本/ASCII发送；连续裸数字必须用换行或至少10ms间隔分开，勿逐字符慢输入。
// 上电/复位PWM=0；发0停止；有效命令持续生效直到下一条命令或复位。
// 每100ms冻结并发送一行：enc=+123,delta=-12,pwm=+1250，末尾显式CR/LF。
// enc是复位以来有符号累计计数；delta是最近100ms净增量(非绝对脉冲总数)；pwm是已接受命令。
// 字段无多余前导零，零也显示+0；RX控制与TX遥测独立运行，发送期间字段不变。
// 方向约定固定为顺时针为正(沿用本次实机观察视角)：正PWM顺时针，enc顺时针增加，delta为正。
// 两方向反转参数均为1；正PWM使IN1=0/IN2=1，原始AB序列00->01->11->10->00减计数。
// 保留旧驱动的即时换向行为，不增加换向死区；STBY由J280底板固定使能。
`timescale 1ns / 1ps
module top #(
    parameter integer MOTOR_DIR_REVERSE = 1,
    parameter integer ENCODER_DIR_REVERSE = 1,
    parameter integer REPORT_MS = 100,
    parameter integer RX_IDLE_MS = 10
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
    localparam integer REPORT_TICKS = 50000 * REPORT_MS;
    localparam integer IDLE_TICKS = 50000 * RX_IDLE_MS;
    localparam integer REPORT_WIDTH = (REPORT_TICKS > 1) ? $clog2(REPORT_TICKS) : 1;
    localparam integer IDLE_WIDTH = (IDLE_TICKS > 1) ? $clog2(IDLE_TICKS) : 1;
    wire [7:0] rx_data;
    wire rx_done, tx_done;
    reg [7:0] tx_data;
    reg tx_send;
    reg signed [15:0] motor_command;
    wire signed [31:0] position_cnt;

    reg rx_started, rx_negative, rx_has_digit, rx_error;
    reg [2:0] rx_digits;
    reg [15:0] rx_value;
    reg [IDLE_WIDTH-1:0] rx_idle_count;
    wire rx_delimiter = (rx_data == 8'h0d) || (rx_data == 8'h0a);
    wire rx_is_digit = (rx_data >= "0") && (rx_data <= "9");
    wire [3:0] rx_digit = rx_data[3:0]; // ASCII数字经rx_is_digit校验后，低四位即数值。
    wire [16:0] next_value = {1'b0, rx_value} * 17'd10 + {13'b0, rx_digit};
    wire rx_timeout = rx_started && (rx_idle_count == IDLE_TICKS - 1);

    // 文本一整条校验成功后才改变电机命令，CRLF的第二个分隔符为空行。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            motor_command <= 0;
            rx_started <= 0; rx_negative <= 0; rx_has_digit <= 0; rx_error <= 0;
            rx_digits <= 0; rx_value <= 0; rx_idle_count <= 0;
        end else if (rx_done) begin
            rx_idle_count <= 0;
            if (rx_delimiter) begin
                if (rx_has_digit && !rx_error)
                    motor_command <= rx_negative ? -$signed(rx_value) : $signed(rx_value);
                rx_started <= 0; rx_negative <= 0; rx_has_digit <= 0; rx_error <= 0;
                rx_digits <= 0; rx_value <= 0;
            end else begin
                rx_started <= 1;
                if (!rx_started && ((rx_data == "+") || (rx_data == "-")))
                    rx_negative <= (rx_data == "-");
                else if (rx_is_digit && !rx_error) begin
                    if ((rx_digits < 4) && (next_value <= 17'd2500)) begin
                        rx_value <= next_value[15:0];
                        rx_digits <= rx_digits + 1'b1;
                        rx_has_digit <= 1;
                    end else rx_error <= 1;
                end else rx_error <= 1;
            end
        end else if (rx_timeout) begin
            if (rx_has_digit && !rx_error)
                motor_command <= rx_negative ? -$signed(rx_value) : $signed(rx_value);
            rx_started <= 0; rx_negative <= 0; rx_has_digit <= 0; rx_error <= 0;
            rx_digits <= 0; rx_value <= 0; rx_idle_count <= 0;
        end else if (rx_started) rx_idle_count <= rx_idle_count + 1'b1;
    end

    TB6612_Motor_driver #(.DIR_REVERSE(MOTOR_DIR_REVERSE))
        motor_inst (
            .clk(clk),
            .rst_n(rst_n),
            .motor_en(rst_n),
            .motor_brake(1'b0),
            .motor_pwm(motor_command),
            .tb_in1(tb_in1),
            .tb_in2(tb_in2),
            .tb_pwm(tb_pwm)
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

    reg [REPORT_WIDTH-1:0] report_count;
    wire report_due = (report_count == REPORT_TICKS - 1);
    reg signed [31:0] last_position;
    // 32位模减法也可处理累计计数器的自然回绕；单窗口位移须在signed32范围内。
    wire signed [31:0] position_delta = position_cnt - last_position;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            report_count <= 0;
            last_position <= 0;
        end else if (report_due) begin
            report_count <= 0;
            last_position <= position_cnt;
        end else report_count <= report_count + 1'b1;
    end

    localparam [3:0] IDLE = 0, LOAD = 1, CONVERT = 2, PREFIX = 3, WAIT_PREFIX = 4,
                     SIGN = 5, WAIT_SIGN = 6, DIGIT = 7, WAIT_DIGIT = 8,
                     CR = 9, WAIT_CR = 10, LF = 11, WAIT_LF = 12;
    reg [3:0] state;
    reg signed [31:0] frame_position, frame_delta, frame_pwm;
    reg [1:0] field_index;
    reg field_negative;
    reg [2:0] prefix_index;
    reg [3:0] digit_index;
    reg digit_started;
    reg [4:0] bit_count;
    reg [71:0] bcd_shift;
    reg [71:0] bcd_adjusted;
    wire [71:0] bcd_next = bcd_adjusted << 1;
    reg [39:0] decimal_digits;
    wire signed [31:0] field_value = (field_index == 0) ? frame_position :
                                    (field_index == 1) ? frame_delta : frame_pwm;
    // unsigned幅值保留-2147483648的绝对值，十位十进制足够表示。
    wire [31:0] field_magnitude = field_value[31] ? (~field_value + 32'd1) : field_value;
    wire [2:0] prefix_length = (field_index == 0) ? 3'd4 : (field_index == 1) ? 3'd7 : 3'd5;
    localparam [31:0] ENC_PREFIX = "enc=";
    localparam [55:0] DELTA_PREFIX = ",delta=";
    localparam [39:0] PWM_PREFIX = ",pwm=";
    wire [7:0] prefix_byte = (field_index == 0) ? ENC_PREFIX[(3-prefix_index)*8 +: 8] :
                             (field_index == 1) ? DELTA_PREFIX[(6-prefix_index)*8 +: 8] :
                                                 PWM_PREFIX[(4-prefix_index)*8 +: 8];

    integer digit;
    always @(*) begin
        bcd_adjusted = bcd_shift;
        for (digit = 0; digit < 10; digit = digit + 1)
            if (bcd_shift[32+digit*4 +: 4] >= 5)
                bcd_adjusted[32+digit*4 +: 4] = bcd_shift[32+digit*4 +: 4] + 4'd3;
    end

    // 逐拍BCD转换，按前缀/符号/有效数字发送，避免宽除法和前导零。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            frame_position <= 0; frame_delta <= 0; frame_pwm <= 0;
            field_index <= 0; field_negative <= 0; prefix_index <= 0;
            digit_index <= 0; digit_started <= 0; bit_count <= 0;
            bcd_shift <= 0; decimal_digits <= 0; tx_data <= 0; tx_send <= 0;
        end else begin
            tx_send <= 0;
            case (state)
                IDLE: begin
                    if (report_due) begin
                        frame_position <= position_cnt;
                        frame_delta <= position_delta;
                        frame_pwm <= {{16{motor_command[15]}}, motor_command};
                        field_index <= 0;
                        state <= LOAD;
                    end
                end
                LOAD: begin
                    bcd_shift <= {40'b0, field_magnitude};
                    field_negative <= field_value[31];
                    bit_count <= 0;
                    state <= CONVERT;
                end
                CONVERT: begin
                    bcd_shift <= bcd_next;
                    if (bit_count == 31) begin
                        decimal_digits <= bcd_next[71:32];
                        prefix_index <= 0;
                        digit_index <= 0;
                        digit_started <= 0;
                        state <= PREFIX;
                    end else bit_count <= bit_count + 1'b1;
                end
                PREFIX: begin
                    tx_data <= prefix_byte;
                    tx_send <= 1;
                    state <= WAIT_PREFIX;
                end
                WAIT_PREFIX: begin
                    if (tx_done) begin
                        if (prefix_index == prefix_length - 1) state <= SIGN;
                        else begin prefix_index <= prefix_index + 1'b1; state <= PREFIX; end
                    end
                end
                SIGN: begin
                    tx_data <= field_negative ? "-" : "+";
                    tx_send <= 1;
                    state <= WAIT_SIGN;
                end
                WAIT_SIGN: if (tx_done) state <= DIGIT;
                DIGIT: begin
                    if (!digit_started && (digit_index < 9) && (decimal_digits[39:36] == 0)) begin
                        decimal_digits <= decimal_digits << 4;
                        digit_index <= digit_index + 1'b1;
                    end else begin
                        tx_data <= 8'h30 + {4'b0, decimal_digits[39:36]};
                        tx_send <= 1;
                        digit_started <= 1;
                        state <= WAIT_DIGIT;
                    end
                end
                WAIT_DIGIT: begin
                    if (tx_done) begin
                        if (digit_index == 9) begin
                            if (field_index == 2) state <= CR;
                            else begin field_index <= field_index + 1'b1; state <= LOAD; end
                        end else begin
                            decimal_digits <= decimal_digits << 4;
                            digit_index <= digit_index + 1'b1;
                            state <= DIGIT;
                        end
                    end
                end
                CR: begin tx_data <= 8'h0d; tx_send <= 1; state <= WAIT_CR; end
                WAIT_CR: if (tx_done) state <= LF;
                LF: begin tx_data <= 8'h0a; tx_send <= 1; state <= WAIT_LF; end
                WAIT_LF: if (tx_done) state <= IDLE;
                default: state <= IDLE;
            endcase
        end
    end
endmodule
