// 项目: 串口接收cmd,控制LED闪烁
`timescale 1ns / 1ps
module acx720_uart_rx_ctrl_led(
        input wire clk,
        input wire rst_n,
        input wire uart_rx,
        output reg LED 
    );

    // 信号
    wire rx_done ;
    wire [7:0] data_byte ;
    reg  [7:0] ctrl ;
    reg [31:0] time_set ;

    // 1. 串口接收Data[7:0]并且指示Rx_Done
    uart_byte_rx  uart_byte_rx_inst (
        .clk(clk),
        .rst_n(rst_n),
        .baud_set(3'd0),
        .uart_rx(uart_rx),
        .rx_done(rx_done),
        .data_byte(data_byte)
    );

    // 2.1 8Byte移位缓存: 窗口缓存,实现每次接收到新的1Byte就直接进行这新的8Byte检测
    reg [7:0] rx_data_pre[0:7] ;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_data_pre[0] <= 8'd0 ;
            rx_data_pre[1] <= 8'd0 ;
            rx_data_pre[2] <= 8'd0 ;
            rx_data_pre[3] <= 8'd0 ;
            rx_data_pre[4] <= 8'd0 ;
            rx_data_pre[5] <= 8'd0 ;
            rx_data_pre[6] <= 8'd0 ;
            rx_data_pre[7] <= 8'd0 ;
        end
        else if (rx_done) begin
            rx_data_pre[0] <= rx_data_pre[1] ;
            rx_data_pre[1] <= rx_data_pre[2] ;
            rx_data_pre[2] <= rx_data_pre[3] ;
            rx_data_pre[3] <= rx_data_pre[4] ;
            rx_data_pre[4] <= rx_data_pre[5] ;
            rx_data_pre[5] <= rx_data_pre[6] ;
            rx_data_pre[6] <= rx_data_pre[7] ;
            rx_data_pre[7] <= data_byte ;
        end
    end

    // 2.2 cmd检查
    always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        ctrl     <= 8'd0;
        time_set <= 32'd0;
    end
    else if (rx_done) begin
        // 当前收到 data_byte = 帧尾 F0
        if ((rx_data_pre[1] == 8'h55) &&
            (rx_data_pre[2] == 8'hA5) &&
            (data_byte      == 8'hF0)) begin

            time_set <= {
                rx_data_pre[3],
                rx_data_pre[4],
                rx_data_pre[5],
                rx_data_pre[6]
            };
            ctrl <= rx_data_pre[7];
        end
    end
end

    // 3. LED控制
    reg [31:0] LED_Cnt;
    reg [2:0]  LED_Status;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            LED_Cnt    <= 32'd0;
            LED_Status <= 3'd0;
            LED        <= 1'b0;
        end

        else if (time_set == 0) begin
            LED_Cnt    <= 32'd0;
            LED_Status <= 3'd0;
            LED        <= 1'b0;
        end

        else if (LED_Cnt >= time_set - 1'b1) begin
            LED_Cnt    <= 32'd0;
            LED         <= ctrl[LED_Status];
            LED_Status <= LED_Status + 1'b1;
        end

        else begin
            LED_Cnt <= LED_Cnt + 1'b1;
        end
    end
endmodule
