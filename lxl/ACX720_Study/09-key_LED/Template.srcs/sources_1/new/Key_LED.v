// 项目: 按键控制LED
`timescale 1ns / 1ps
module Key_LED(
        input  wire clk,
        input  wire rst_n,
        input  wire [3:0] key_in,
        output reg  [7:0] LED
    );

    // 1. 按键例化
    wire [3:0] key_release;    // 松开事件，持续1个clk

    key key_inst_1 (
        .clk(clk),
        .rst_n(rst_n),
        .key_in(key_in[0]),
        .key_state(),
        .key_press(),
        .key_release(key_release[0]),
        .key_change()
    );

    key key_inst_2 (
        .clk(clk),
        .rst_n(rst_n),
        .key_in(key_in[1]),
        .key_state(),
        .key_press(),
        .key_release(key_release[1]),
        .key_change()
    );

    key key_inst_3 (
        .clk(clk),
        .rst_n(rst_n),
        .key_in(key_in[2]),
        .key_state(),
        .key_press(),
        .key_release(key_release[2]),
        .key_change()
    );

    key key_inst_4 (
        .clk(clk),
        .rst_n(rst_n),
        .key_in(key_in[3]),
        .key_state(),
        .key_press(),
        .key_release(key_release[3]),
        .key_change()
    );

    // 2. LED配置
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            LED <= 8'd0;
        end
        else begin
            if (key_release[0]) 
                LED <= LED + 1'b1 ;
            else if (key_release[1])
                LED <= LED - 1'b1 ;
            else if (key_release[2])
                LED <= {LED[6:0] , LED[7]} ;
            else if (key_release[3])
                LED <= {LED[0] , LED[7:1]} ;
        end
    end

endmodule
