`timescale 1ns / 1ps
// 按键低有效、LED高有效；复位时全部熄灭。
module LED (
    input wire rst_n,
    input wire [2:0] key_state,
    output wire [2:0] led
);
    assign led = rst_n ? ~key_state : 3'b000;
endmodule
