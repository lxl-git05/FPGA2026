`timescale 1ns / 1ps
// Only this layer knows FPGA pins, ADC forwarding, Key debounce and byte UART.
module board_io #(
    parameter integer MOTOR_DIR_REVERSE=1,ENCODER_DIR_REVERSE=1
)(input wire clk,rst_n,key_in,key2_in,encoder_a,encoder_b,uart_rx,
    input wire [9:0] adc_data_in,input wire adc_otr,
    input wire [11:0] rail_low,rail_high,
    input wire motor_enable,input wire signed [31:0] motor_pwm_ticks,
    input wire [7:0] tx_data,input wire tx_send,
    output wire uart_tx,tx_done,output wire [7:0] rx_data,output wire rx_done,key_press,key2_press,key2_state,
    output wire adc_clk,adc_oe_n,tb_pwm,tb_in1,tb_in2,
    output wire [11:0] raw_adc,angle_adc,
    output wire raw_valid,raw_otr,window_valid,angle_valid,
    output wire signed [31:0] encoder_count);
    key k1(.clk(clk),.rst_n(rst_n),.key_in(key_in),.key_press(key_press),
        .key_state(),.key_release(),.key_change());
    key k2(.clk(clk),.rst_n(rst_n),.key_in(key2_in),.key_press(key2_press),
        .key_state(key2_state),.key_release(),.key_change());
    encoder_quad #(.DIR_REVERSE(ENCODER_DIR_REVERSE)) enc(.clk(clk),.rst_n(rst_n),
        .encoder_a(encoder_a),.encoder_b(encoder_b),.position_zero(1'b0),.position_cnt(encoder_count));
    adc_frontend ad(.clk(clk),.rst_n(rst_n),.adc_data_in(adc_data_in),.adc_otr(adc_otr),
        .rail_low(rail_low),.rail_high(rail_high),.adc_clk(adc_clk),.adc_oe_n(adc_oe_n),
        .raw_adc(raw_adc),.angle_adc(angle_adc),.raw_valid(raw_valid),.raw_otr(raw_otr),
        .window_valid(window_valid),.angle_valid(angle_valid));
    uart_byte_rx rx(.clk(clk),.rst_n(rst_n),.baud_set(3'd4),.uart_rx(uart_rx),.data_byte(rx_data),.rx_Done(rx_done));
    uart_byte_tx tx(.clk(clk),.rst_n(rst_n),.baud_set(3'd4),.data_byte(tx_data),.send_en(tx_send),
        .uart_tx(uart_tx),.tx_done(tx_done),.uart_state());
    TB6612_Motor_driver #(.DIR_REVERSE(MOTOR_DIR_REVERSE)) motor(.clk(clk),.rst_n(rst_n),
        .motor_en(motor_enable),.motor_brake(1'b0),.motor_pwm(motor_pwm_ticks[15:0]),
        .tb_in1(tb_in1),.tb_in2(tb_in2),.tb_pwm(tb_pwm));
endmodule
