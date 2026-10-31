`timescale 1ns / 1ps
// J280/GW2A-55C 模块化倒立摆；50MHz，SW5 复位，K1 启动/停止。
// 上电后为 STOPPED；config_bank 默认双环 + 自动摆起。直立 ADC 实测为 2180；
// config_bank 的 center_adc 默认值为 2240，请通过 @goal_A 将其设为实测值。
// 模块：board_io、command_rx/config_bank、safety_guard、swing_up、run_control、
// cascade_control（两个流水线 PID_Core）、telemetry_tx。无 Protocol V1 或持久化。
// A：ADC 目标/实际、PWM 百分比设定；B：编码器计数目标/实际、ADC 偏移设定。
// 接收 @Kp_A/Ki_A/Kd_A/goal_A 及 B 组对应变体，格式为十进制$#。发送六个 %.6f 字段 + CRLF，50Hz。
// 内环/外环默认 5/50ms；1040 计数/转；顺时针电机/编码器为正。
// 观察到正反馈后，内环 PWM 极性已反转；方向约定不变。
// 外环修正方向：内环目标 = 直立 ADC + 外环 PID 输出。
// 平衡范围使用每个 5ms 内环 ADC 快照；调试时绕过 OTR/窗口/过期检查。
// XH1 使用 B 桥。故障门控覆盖所有 PWM 产生者；仅失衡恢复是自动的。
// 失衡自动重启：进入 BALANCE 后，若角度超出 fall_adc 或位置移动速度大于 FALL_SPEED_CPS，
// 则执行软复位，然后等待角度进入回中区 RESTART_CENTER_ADC±RESTART_ADC
// （默认 0±100，12位角度在 0/4096 处回绕），并自动重新进入 AUTO_SWING。
// K1 始终优先；真实故障仍锁存 FAULT。
module Top #(
    parameter integer MOTOR_DIR_REVERSE=1,ENCODER_DIR_REVERSE=1,
    parameter integer CASCADE_SIGN=1,ANGLE_OUTPUT_SIGN=-1,COUNTS_PER_REV=1040,
    parameter integer ADC_RANGE_ONLY=1, // 1只保留PID采样值范围保护，改0恢复其他ADC判定。
    parameter integer RESTART_ADC=100, // 落摆后回中区半宽，ADC码。
    parameter integer RESTART_CENTER_ADC=0, // 回中区中心，ADC码；0=零点，窗口跨0/4096回绕。
    parameter integer RESTART_CONFIRM_MS=500, // 回中连续确认时间，ms。
    parameter integer FALL_SPEED_CPS=1040, // 位置变化速度上限，counts/s；1040=1圈/s。
    parameter integer FALL_SPEED_WINDOW_MS=1000 // 测速窗口，ms。
)(input wire clk,rst_n,key_in,encoder_a,encoder_b,uart_rx,
    input wire [9:0] adc_data_in,input wire adc_otr,
    output wire uart_tx,adc_clk,adc_oe_n,tb_in1,tb_in2,tb_pwm,
    output wire [2:0] led);
    wire dual_loop;
    wire auto_start;
    wire [15:0] period_a_ms;
    wire [15:0] period_b_ms;
    wire [11:0] capture_adc;
    wire [11:0] fall_adc;
    wire [7:0] kick_percent;
    wire [15:0] kick_ms;
    wire [15:0] judge_ms;
    wire [15:0] swing_timeout_ms;
    wire [15:0] adc_timeout_ms;
    wire [11:0] rail_low;
    wire [11:0] rail_high;
    wire [15:0] outer_limit_adc;
    wire [7:0] inner_limit_percent;
    wire [7:0] inner_i_percent;
    wire [15:0] outer_i_adc;
    wire [31:0] travel_counts;
    wire signed [31:0] kp_a,ki_a,kd_a,kp_b,ki_b,kd_b,center_adc,goal_position;
    wire [31:0] epoch_a,epoch_b;
    wire [7:0] rx_data,tx_data,write_id;
    wire rx_done,tx_done,tx_send,write_valid,config_ready,key_press;
    wire signed [63:0] write_micro;
    wire signed [31:0] encoder_count,position_origin,position_count;
// 累计计数转单圈计数，兼容反转产生的负数。
wire signed [31:0] count_rem = position_count % 32'sd1040;
wire [31:0] single_count =
    count_rem[31] ? count_rem + 32'sd1040 : count_rem;

// 角度×1000000，保留六位小数。
wire [63:0] angle_micro =
    ({32'd0, single_count} * 64'd360000000) / 64'd1040;

    wire signed [32:0] relative_position={encoder_count[31],encoder_count}-{position_origin[31],position_origin};
    assign position_count=(relative_position>33'sd2147483647)?32'sh7fffffff:
                          (relative_position< -33'sd2147483648)?32'sh80000000:relative_position[31:0];
    wire [11:0] raw_adc,angle_adc;
    wire raw_valid,raw_otr,window_valid,angle_valid;
    wire sensor_ok,capture_allowed,balance_safe,position_safe,fault_now;
    wire capture_angle_valid=ADC_RANGE_ONLY?sensor_ok:angle_valid;
    wire [3:0] fault_reason,fault_code;
    wire [2:0] state;
    wire active,balancing,swing_enable,motor_enable,capture_clear,capture_request,swing_timed_out;
    wire signed [31:0] pid_pwm_ticks,swing_pwm_ticks,motor_pwm_ticks;
    wire signed [31:0] a_goal,a_real,a_set_ticks,b_goal,b_real,b_set_adc;
    wire a_done,b_done,telemetry_busy,a_sample_valid;
    wire [11:0] a_sample_adc;
    reg [15:0] ms_counter;
    wire ms_tick=(ms_counter==16'd49999);
    reg [4:0] telemetry_count;
    wire send_frame=ms_tick&&(telemetry_count==19);
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin ms_counter<=0; telemetry_count<=0; end
        else begin
            ms_counter<=ms_tick?16'd0:ms_counter+1'b1;
            if(ms_tick) telemetry_count<=(telemetry_count==19)?5'd0:telemetry_count+1'b1;
        end
    end
    assign led={(state==4),balancing,active};
    board_io #(.MOTOR_DIR_REVERSE(MOTOR_DIR_REVERSE),.ENCODER_DIR_REVERSE(ENCODER_DIR_REVERSE)) io(
        .clk(clk),.rst_n(rst_n),.key_in(key_in),.encoder_a(encoder_a),.encoder_b(encoder_b),.uart_rx(uart_rx),
        .adc_data_in(adc_data_in),.adc_otr(adc_otr),.rail_low(rail_low),.rail_high(rail_high),
        .motor_enable(motor_enable),.motor_pwm_ticks(motor_pwm_ticks),.tx_data(tx_data),.tx_send(tx_send),
        .uart_tx(uart_tx),.tx_done(tx_done),.rx_data(rx_data),.rx_done(rx_done),.key_press(key_press),
        .adc_clk(adc_clk),.adc_oe_n(adc_oe_n),.tb_pwm(tb_pwm),.tb_in1(tb_in1),.tb_in2(tb_in2),
        .raw_adc(raw_adc),.angle_adc(angle_adc),.raw_valid(raw_valid),.raw_otr(raw_otr),
        .window_valid(window_valid),.angle_valid(angle_valid),.encoder_count(encoder_count));
    command_rx commands(.clk(clk),.rst_n(rst_n),.rx_data(rx_data),.rx_done(rx_done),
        .write_valid(write_valid),.write_id(write_id),.write_micro(write_micro));
    config_bank #(.COUNTS_PER_REV(COUNTS_PER_REV)) configuration(.clk(clk),.rst_n(rst_n),.stopped(!active),.write_valid(write_valid),
        .write_id(write_id),.write_micro(write_micro),.ready(config_ready),
        .dual_loop(dual_loop),
        .auto_start(auto_start),
        .period_a_ms(period_a_ms),
        .period_b_ms(period_b_ms),
        .capture_adc(capture_adc),
        .fall_adc(fall_adc),
        .kick_percent(kick_percent),
        .kick_ms(kick_ms),
        .judge_ms(judge_ms),
        .swing_timeout_ms(swing_timeout_ms),
        .adc_timeout_ms(adc_timeout_ms),
        .rail_low(rail_low),
        .rail_high(rail_high),
        .outer_limit_adc(outer_limit_adc),
        .inner_limit_percent(inner_limit_percent),
        .inner_i_percent(inner_i_percent),
        .outer_i_adc(outer_i_adc),
        .travel_counts(travel_counts),
        .kp_a(kp_a),
        .ki_a(ki_a),
        .kd_a(kd_a),
        .kp_b(kp_b),
        .ki_b(ki_b),
        .kd_b(kd_b),
        .center_adc(center_adc),
        .goal_position(goal_position),
        .epoch_a(epoch_a),
        .epoch_b(epoch_b));
    safety_guard #(.ADC_RANGE_ONLY(ADC_RANGE_ONLY)) guard(.clk(clk),.rst_n(rst_n),.ms_tick(ms_tick),.active(active),.balancing(balancing),
        .raw_valid(raw_valid),.raw_otr(raw_otr),.angle_valid(angle_valid),.raw_adc(raw_adc),.angle_adc(angle_adc),
        .balance_sample_valid(a_sample_valid),.balance_angle_adc(a_sample_adc),
        .rail_low(rail_low),.rail_high(rail_high),.capture_adc(capture_adc),.fall_adc(fall_adc),
        .center_adc(center_adc),.position_count(position_count),.travel_counts(travel_counts),.adc_timeout_ms(adc_timeout_ms),
        .sensor_ok(sensor_ok),.capture_allowed(capture_allowed),.balance_safe(balance_safe),
        .position_safe(position_safe),.fault_now(fault_now),.fault_reason(fault_reason));
    swing_up swing(.clk(clk),.rst_n(rst_n),.ms_tick(ms_tick),.enable(swing_enable),.auto_mode(auto_start),
        .angle_valid(capture_angle_valid),.capture_allowed(capture_allowed),.angle_adc(angle_adc),.capture_adc(capture_adc),
        .center_adc(center_adc),.kick_percent(kick_percent),.kick_ms(kick_ms),.judge_ms(judge_ms),
        .swing_timeout_ms(swing_timeout_ms),.swing_pwm_ticks(swing_pwm_ticks),
        .capture_request(capture_request),.timed_out(swing_timed_out));
    run_control #(.RESTART_ADC(RESTART_ADC),.RESTART_CENTER_ADC(RESTART_CENTER_ADC),
        .RESTART_CONFIRM_MS(RESTART_CONFIRM_MS),
        .FALL_SPEED_CPS(FALL_SPEED_CPS),.FALL_SPEED_WINDOW_MS(FALL_SPEED_WINDOW_MS)) run(
        .clk(clk),.rst_n(rst_n),.ms_tick(ms_tick),.key_press(key_press),.sensor_ok(sensor_ok),.position_safe(position_safe),
        .config_ready(config_ready),.auto_start(auto_start),.fault_now(fault_now),.fault_reason(fault_reason),
        .capture_request(capture_request),.swing_timed_out(swing_timed_out),.encoder_count(encoder_count),
        .pid_pwm_ticks(pid_pwm_ticks),.swing_pwm_ticks(swing_pwm_ticks),.state(state),.fault_code(fault_code),
        .position_origin(position_origin),.capture_clear(capture_clear),.active(active),.balancing(balancing),
        .swing_enable(swing_enable),.motor_enable(motor_enable),.motor_pwm_ticks(motor_pwm_ticks),
        .position_count(position_count),.angle_adc(angle_adc),.angle_valid(angle_valid));
    cascade_control #(.CASCADE_SIGN(CASCADE_SIGN),.ANGLE_OUTPUT_SIGN(ANGLE_OUTPUT_SIGN)) controller(
        .clk(clk),.rst_n(rst_n),.ms_tick(ms_tick),.enable(balancing&&!fault_now&&!key_press),.capture_clear(capture_clear),
        .dual_loop(dual_loop),.period_a_ms(period_a_ms),.period_b_ms(period_b_ms),
        .outer_limit_adc(outer_limit_adc),.outer_i_adc(outer_i_adc),
        .inner_limit_percent(inner_limit_percent),.inner_i_percent(inner_i_percent),
        .center_adc(center_adc),.goal_position(goal_position),.position_count(position_count),.angle_adc(angle_adc),
        .kp_a(kp_a),.ki_a(ki_a),.kd_a(kd_a),.kp_b(kp_b),.ki_b(ki_b),.kd_b(kd_b),
        .epoch_a(epoch_a),.epoch_b(epoch_b),.pid_pwm_ticks(pid_pwm_ticks),
        .a_goal(a_goal),.a_real(a_real),.a_set_ticks(a_set_ticks),.b_goal(b_goal),.b_real(b_real),.b_set_adc(b_set_adc),
        .a_done(a_done),.b_done(b_done),.a_sample_valid(a_sample_valid),.a_sample_adc(a_sample_adc));
    telemetry_tx telemetry(.clk(clk),.rst_n(rst_n),.send_frame(send_frame),.tx_done(tx_done),
        .a_goal(a_goal),.a_real(a_real),.a_set_ticks(a_set_ticks),.b_goal(b_goal),.b_real(b_real),.b_set_adc(b_set_adc),
        .tx_data(tx_data),.tx_send(tx_send),.busy(telemetry_busy));
endmodule
