`timescale 1ns / 1ps
// J280：50MHz，SW5低有效复位，上电复位后LED1~3熄灭。
// SW1/SW2/SW3消抖后分别控制LED1/LED2/LED3，按住亮、松开灭。
module top (
    input wire clk,
    input wire rst_n,
    input wire [2:0] key_in,
    output wire [2:0] led
);
    wire [2:0] key_state;

    genvar i;
    generate
        for (i = 0; i < 3; i = i + 1) begin : gen_keys
            key #(.KEY_UNPRESSED(1'b1))
                key_inst (
                    .clk(clk),
                    .rst_n(rst_n),
                    .key_in(key_in[i]),
                    .key_state(key_state[i]),
                    .key_press(),
                    .key_release(),
                    .key_change()
                );
        end
    endgenerate

    LED
        LED_inst (
            .rst_n(rst_n),
            .key_state(key_state),
            .led(led)
        );
endmodule
