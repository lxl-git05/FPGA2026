// 3PA1030并行ADC：默认25MHz时钟，每62.5us取样，16点平均后每1ms发布。
// data为10位码左移2位后的平均结果；data_valid单拍，结果保持至下次更新。
// raw_data是窗口末次原始码，data_otr是窗口16个取样点的超量程逻辑或。
`timescale 1ns / 1ps
module adc #(
    parameter integer CLK_DIV = 1,
    parameter integer SAMPLE_TICKS = 3125,
    parameter integer AVG_LOG2 = 4
)(
    input wire clk,
    input wire rst_n,
    output reg adc_clk,
    output wire adc_oe_n,
    output wire adc_stby_n,
    input wire adc_otr,
    input wire [9:0] adc_data_in,
    output reg [11:0] data,
    output reg data_valid,
    output reg [9:0] raw_data,
    output reg data_otr
);
    localparam integer DIV_WIDTH = (CLK_DIV > 1) ? $clog2(CLK_DIV) : 1;
    localparam integer TIMER_WIDTH = (SAMPLE_TICKS > 1) ? $clog2(SAMPLE_TICKS) : 1;
    localparam integer COUNT_WIDTH = (AVG_LOG2 > 0) ? AVG_LOG2 : 1;
    localparam integer SUM_WIDTH = 12 + AVG_LOG2;
    reg [DIV_WIDTH-1:0] div_count;
    reg [TIMER_WIDTH-1:0] sample_timer;
    reg [COUNT_WIDTH-1:0] sample_count;
    reg [9:0] captured_data;
    reg captured_otr, window_otr;
    reg [SUM_WIDTH-1:0] sample_sum;
    wire sample_due = (sample_timer == SAMPLE_TICKS - 1);
    wire [SUM_WIDTH-1:0] sum_next = sample_sum +
                                   {{AVG_LOG2{1'b0}}, captured_data, 2'b00};

    assign adc_oe_n = !rst_n;
    // 沿用原端口名；3PA1030的STBY实际高有效待机，0为正常工作。
    // J280底板将STBY接地，该输出不需要接到板级顶层。
    assign adc_stby_n = 1'b0;

    // https://static.3peak.com/res/doc/ds/Datasheet_3PA1030.pdf
    // 数据延迟典型25ns，不能在25MHz时钟的半周期20ns处假定新数据已稳定。
    // 在下一次转发上升沿前锁存上一周期数据，留出约一个ADC周期的传播时间。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            adc_clk <= 0;
            div_count <= 0;
            captured_data <= 0;
            captured_otr <= 0;
        end else if (div_count == CLK_DIV - 1) begin
            div_count <= 0;
            adc_clk <= ~adc_clk;
            if (!adc_clk) begin
                captured_data <= adc_data_in;
                captured_otr <= adc_otr;
            end
        end else div_count <= div_count + 1'b1;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sample_timer <= 0;
            sample_count <= 0;
            sample_sum <= 0;
            window_otr <= 0;
            data <= 0;
            data_valid <= 0;
            raw_data <= 0;
            data_otr <= 0;
        end else begin
            data_valid <= 0;
            if (sample_due) begin
                sample_timer <= 0;
                // 包含本次样本后再发布，避免少算最后一个样本。
                if (sample_count == (1 << AVG_LOG2) - 1) begin
                    data <= sum_next >> AVG_LOG2;
                    raw_data <= captured_data;
                    data_otr <= window_otr | captured_otr;
                    data_valid <= 1;
                    sample_count <= 0;
                    sample_sum <= 0;
                    window_otr <= 0;
                end else begin
                    sample_count <= sample_count + 1'b1;
                    sample_sum <= sum_next;
                    window_otr <= window_otr | captured_otr;
                end
            end else sample_timer <= sample_timer + 1'b1;
        end
    end
endmodule
