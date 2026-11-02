`timescale 1ns / 1ps
// J280/GW2A-55C modular inverted pendulum; 50MHz, SW5 reset, K1 start/stop.
// Power-on STOPPED; current defaults single-loop + manual capture. Upright ADC=2180 (measured 2026-10-21).
// Modules: board_io, command_rx/config_bank, safety_guard, swing_up, run_control,
// cascade_control(two pipelined PID_Core), telemetry_tx. No Protocol V1 or persistence.
// A: ADC goal/real, PWM percent set; B: encoder-count goal/real, ADC-offset set.
// RX @Kp_A/Ki_A/Kd_A/goal_A and B variants =decimal$#. TX six %.6f fields + CRLF, 50Hz.
// Inner/outer defaults 5/50ms; 1040 counts/rev; clockwise motor/encoder positive.
// Inner PWM polarity reversed after observed positive feedback; direction conventions unchanged.
// Outer correction direction: inner goal = upright ADC + outer PID output.
// Balance range uses each 5ms inner-loop ADC snapshot; OTR/window/stale checks bypassed in debug.
// XH1 uses B bridge. Fault gate overrides every PWM producer; no automatic fault restart.
// K2: one-revolution position-loop trajectory (cubic position / quadratic velocity),
// started only in normal BALANCE; the outer PID tracks it and holds the new position.
module Top #(
    parameter integer MOTOR_DIR_REVERSE=1,ENCODER_DIR_REVERSE=1,
    parameter integer CASCADE_SIGN=1,ANGLE_OUTPUT_SIGN=-1,COUNTS_PER_REV=1040,
    parameter integer ADC_RANGE_ONLY=1 // 1只保留PID采样值范围保护，改0恢复其他ADC判定。
)(input wire clk,rst_n,key_in,key2_in,encoder_a,encoder_b,uart_rx,
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
    wire rx_done,tx_done,tx_send,write_valid,config_ready,key_press,key2_press;
    wire signed [63:0] write_micro;
    wire signed [31:0] encoder_count,position_origin,position_count;
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
    wire auto_retry;
    wire signed [31:0] move_target;
    wire move_active,move_hold;
    wire move_enable=move_active||move_hold;
    wire signed [31:0] pid_pwm_ticks,swing_pwm_ticks,motor_pwm_ticks;
    wire signed [31:0] a_goal,a_real,a_set_ticks,b_goal,b_real,b_set_adc;
    wire a_done,b_done,telemetry_busy,a_sample_valid;
    wire returning;
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
        .clk(clk),.rst_n(rst_n),.key_in(key_in),.key2_in(key2_in),.encoder_a(encoder_a),.encoder_b(encoder_b),.uart_rx(uart_rx),
        .adc_data_in(adc_data_in),.adc_otr(adc_otr),.rail_low(rail_low),.rail_high(rail_high),
        .motor_enable(motor_enable),.motor_pwm_ticks(motor_pwm_ticks),.tx_data(tx_data),.tx_send(tx_send),
        .uart_tx(uart_tx),.tx_done(tx_done),.rx_data(rx_data),.rx_done(rx_done),.key_press(key_press),.key2_press(key2_press),
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
        .returning(returning),
        .sensor_ok(sensor_ok),.capture_allowed(capture_allowed),.balance_safe(balance_safe),
        .position_safe(position_safe),.fault_now(fault_now),.fault_reason(fault_reason));
    swing_up swing(.clk(clk),.rst_n(rst_n),.ms_tick(ms_tick),.enable(swing_enable),.auto_mode(auto_start),
        .angle_valid(capture_angle_valid),.capture_allowed(capture_allowed),.angle_adc(angle_adc),.capture_adc(capture_adc),
        .center_adc(center_adc),.kick_percent(kick_percent),.kick_ms(kick_ms),.judge_ms(judge_ms),
        .swing_timeout_ms(swing_timeout_ms),.swing_pwm_ticks(swing_pwm_ticks),
        .capture_request(capture_request),.timed_out(swing_timed_out));
    run_control run(.clk(clk),.rst_n(rst_n),.key_press(key_press),.sensor_ok(sensor_ok),.position_safe(position_safe),
        .config_ready(config_ready),.auto_start(auto_start),.fault_now(fault_now),.fault_reason(fault_reason),
        .capture_request(capture_request),.swing_timed_out(swing_timed_out),.angle_adc(angle_adc),
        .ms_tick(ms_tick),
        .encoder_count(encoder_count),
        .pid_pwm_ticks(pid_pwm_ticks),.swing_pwm_ticks(swing_pwm_ticks),.state(state),.fault_code(fault_code),
        .position_origin(position_origin),.capture_clear(capture_clear),.auto_retry(auto_retry),.active(active),.balancing(balancing),
        .swing_enable(swing_enable),.motor_enable(motor_enable),.motor_pwm_ticks(motor_pwm_ticks));
    // K2 one-revolution position reference. Only in normal BALANCE (not auto-retry).
    position_profile #(
        .COUNTS_PER_REV(COUNTS_PER_REV),
        .MOVE_SIGN(1),
        .STEP_MS(50),
        .MOVE_TIME_MS(3000),
        .MAX_SPEED_COUNTS_PER_S(520)
    ) profile(
        .clk(clk),.rst_n(rst_n),.ms_tick(ms_tick),
        .start(key2_press&&balancing&&dual_loop&&!auto_retry&&!fault_now),
        .abort(!balancing||!dual_loop||auto_retry||fault_now),
        .position_count(position_count),
        .goal_position(goal_position),
        .move_target(move_target),
        .move_active(move_active),
        .move_hold(move_hold));
    cascade_control #(.CASCADE_SIGN(CASCADE_SIGN),.ANGLE_OUTPUT_SIGN(ANGLE_OUTPUT_SIGN),.REV_COUNTS(COUNTS_PER_REV)) controller(
        .clk(clk),.rst_n(rst_n),.ms_tick(ms_tick),.enable(balancing&&!fault_now&&!key_press),.capture_clear(capture_clear),
        .auto_retry(auto_retry),
        .move_enable(move_enable),.move_target(move_target),
        .dual_loop(dual_loop),.period_a_ms(period_a_ms),.period_b_ms(period_b_ms),
        .outer_limit_adc(outer_limit_adc),.outer_i_adc(outer_i_adc),
        .inner_limit_percent(inner_limit_percent),.inner_i_percent(inner_i_percent),
        .center_adc(center_adc),.goal_position(goal_position),.position_count(position_count),.angle_adc(angle_adc),
        .kp_a(kp_a),.ki_a(ki_a),.kd_a(kd_a),.kp_b(kp_b),.ki_b(ki_b),.kd_b(kd_b),
        .epoch_a(epoch_a),.epoch_b(epoch_b),.pid_pwm_ticks(pid_pwm_ticks),
        .a_goal(a_goal),.a_real(a_real),.a_set_ticks(a_set_ticks),.b_goal(b_goal),.b_real(b_real),.b_set_adc(b_set_adc),
        .returning(returning),
        .a_done(a_done),.b_done(b_done),.a_sample_valid(a_sample_valid),.a_sample_adc(a_sample_adc));
    telemetry_tx telemetry(.clk(clk),.rst_n(rst_n),.send_frame(send_frame),.tx_done(tx_done),
        .a_goal(a_goal),.a_real(a_real),.a_set_ticks(a_set_ticks),.b_goal(b_goal),.b_real(b_real),.b_set_adc(b_set_adc),
        .tx_data(tx_data),.tx_send(tx_send),.busy(telemetry_busy));
endmodule
