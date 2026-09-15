// 项目2: LED翻转
`timescale 1ns / 1ps
module bin_counter
    # (
        parameter integer CNT_MAX = 25_000_000 
    )
    (
        input  wire clk,
        input  wire rst_n ,
        output reg LED
    );

    // 声明变量
    reg [25:0] cnt ;

    // 书写逻辑
    // 1. 时钟
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            cnt <= 26'b0 ;
        else if (cnt == CNT_MAX - 1) // 0.5s归零一次
            cnt <= 26'b0 ;
        else begin
            cnt <= cnt + 1'b1 ;
        end
    end

    // 2. LED翻转
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            LED <= 1'b0 ;
        else if (cnt == CNT_MAX - 1)
            LED <= ~LED ;   // LED翻转
    end

    ila_0 your_instance_name (
	.clk(clk), // input wire clk


	.probe0(cnt), // input wire [25:0]  probe0  
	.probe1(LED) // input wire [0:0]  probe1
);

endmodule
