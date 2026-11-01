`timescale 1ns / 1ps
// ASCII only: eight case-sensitive commands, max32 bytes, 100ms timeout.
// Valid syntax emits an ID and signed micro-units; config_bank checks physical limits.
module command_rx(input wire clk, rst_n, input wire [7:0] rx_data,
    input wire rx_done, output reg write_valid, output reg [7:0] write_id,
    output reg signed [63:0] write_micro);
    // RX：语法状态与多周期单位换算。先归一化为百万分之一，再作有理数换算。
    localparam [3:0] R_IDLE=0, R_NAME=1, R_NUMBER=2, R_HASH=3,
                     R_SCALE=4, R_SCALE_MUL=5, R_SCALE_CHECK=6;
    reg [3:0] rx_state;
    reg [5:0] frame_length;
    reg [47:0] name_shift;
    reg [2:0] name_length, frac_digits;
    reg [2:0] param_kind;
    reg number_started, number_negative, number_dot, number_has_digit;
    reg [63:0] number_mantissa;
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
    reg [127:0] multiply_acc, multiply_a, multiply_result;
    reg [63:0] multiply_b;
    reg [6:0] multiply_count;
    wire [127:0] multiply_next = multiply_acc + (multiply_b[0] ? multiply_a : 128'd0);
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
            number_mantissa <= 0;
            multiply_acc <= 0; multiply_a <= 0; multiply_b <= 0;
            multiply_result <= 0; multiply_count <= 0;
            write_valid <= 0; write_id <= 0; write_micro <= 0;
        end else begin
            write_valid <= 0;
            if (rx_done && (rx_data == "@")) begin

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
                            if ((name_length == 4) && (name_shift == "Kp_A")) begin param_kind <= 3'd0; rx_state <= R_NUMBER; end
                            else if ((name_length == 4) && (name_shift == "Ki_A")) begin param_kind <= 3'd1; rx_state <= R_NUMBER; end
                            else if ((name_length == 4) && (name_shift == "Kd_A")) begin param_kind <= 3'd2; rx_state <= R_NUMBER; end
                            else if ((name_length == 6) && (name_shift == "goal_A")) begin param_kind <= 3'd3; rx_state <= R_NUMBER; end
                            else if ((name_length == 4) && (name_shift == "Kp_B")) begin param_kind <= 3'd4; rx_state <= R_NUMBER; end
                            else if ((name_length == 4) && (name_shift == "Ki_B")) begin param_kind <= 3'd5; rx_state <= R_NUMBER; end
                            else if ((name_length == 4) && (name_shift == "Kd_B")) begin param_kind <= 3'd6; rx_state <= R_NUMBER; end
                            else if ((name_length == 6) && (name_shift == "goal_B")) begin param_kind <= 3'd7; rx_state <= R_NUMBER; end
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
                R_SCALE_MUL: begin
                    multiply_acc <= multiply_next;
                    multiply_a <= multiply_a << 1;
                    multiply_b <= multiply_b >> 1;
                    if (multiply_count == 0) begin
                        multiply_result <= multiply_next;
                        rx_state <= R_SCALE_CHECK;
                    end else multiply_count <= multiply_count - 1'b1;
                end
                R_SCALE_CHECK: begin
                    if (multiply_result <= (number_negative ? 128'd9223372036854775808 : 128'd9223372036854775807)) begin
                        write_id <= {5'b0,param_kind};
                        write_micro <= number_negative ? -$signed(multiply_result[63:0]) : $signed(multiply_result[63:0]);
                        write_valid <= 1;
                    end
                    rx_state <= R_IDLE;
                end
                default: ;
            endcase
        end
    end
        end
endmodule
