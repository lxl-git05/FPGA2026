// 工程：J280/3PA1030 ADC采集与串口观测，50MHz，SW5低有效复位。
// 模块：adc并行采集/平均、uart_byte_tx串口发送；复用相邻uart_loopback工程的TX源码。
// 业务：默认每62.5us取样、16点平均，每1ms更新；每100ms上传最新完整快照。
// UART：115200/8N1，ASCII行：adc=2060,raw=0515,otr=0,seq=0000000100,update_us=001000，末尾CR/LF。
// adc为12位尺度均值；raw为同窗口末次10位原码；otr为该窗口取样点超量程或；seq为更新计数。
// 固定宽度十进制、前导零；发送期间字段冻结，ADC持续工作；复位清零，首个有效结果前不发送。
// STBY在底板接地，顶层不引出；这里只读ADC并周期上传，不含PID和UART接收业务。
`timescale 1ns / 1ps
module top #(
    parameter integer CLK_FREQ_HZ = 50_000_000,
    parameter integer ADC_CLK_DIV = 1,
    parameter integer SAMPLE_TICKS = 3125,
    parameter integer AVG_LOG2 = 4,
    parameter integer REPORT_MS = 100
)(
    input wire clk,
    input wire rst_n,
    input wire [9:0] adc_data_in,
    input wire adc_otr,
    output wire adc_clk,
    output wire adc_oe_n,
    output wire uart_tx
);
    localparam integer REPORT_TICKS = (CLK_FREQ_HZ / 1000) * REPORT_MS;
    localparam integer REPORT_WIDTH = (REPORT_TICKS > 1) ? $clog2(REPORT_TICKS) : 1;
    localparam integer UPDATE_US = (SAMPLE_TICKS * (1 << AVG_LOG2)) /
                                  (CLK_FREQ_HZ / 1_000_000);
    localparam integer LINE_BYTES = 57;
    localparam [LINE_BYTES*8-1:0] LINE_TEMPLATE =
        {"adc=0000,raw=0000,otr=0,seq=0000000000,update_us=000000", 8'h0d, 8'h0a};
    localparam [2:0] IDLE = 0, LOAD = 1, CONVERT = 2, SEND = 3, WAIT_TX = 4;
    wire [11:0] adc_value;
    wire [9:0] adc_raw;
    wire adc_valid, adc_over;
    wire tx_done;
    reg [REPORT_WIDTH-1:0] report_timer;
    reg sample_ready;
    reg [31:0] sample_seq;
    reg [11:0] frame_adc;
    reg [9:0] frame_raw;
    reg frame_otr;
    reg [31:0] frame_seq;
    reg [2:0] state;
    reg [1:0] field_index;
    reg [4:0] bit_count;
    reg [71:0] bcd_shift;
    reg [71:0] bcd_adjusted;
    wire [71:0] bcd_next = bcd_adjusted << 1;
    reg [15:0] adc_bcd, raw_bcd;
    reg [39:0] seq_bcd;
    reg [5:0] char_index;
    reg [7:0] tx_data;
    reg tx_send;
    wire report_due = (report_timer == REPORT_TICKS - 1);
    wire [REPORT_WIDTH:0] report_next = {1'b0, report_timer} + 1'b1;

    // 只用于编译期常量转换，不生成运行时除法器。
    function [39:0] constant_bcd;
        input [31:0] value;
        reg [71:0] work_bits;
        integer bit_index, digit;
        begin
            work_bits = {40'b0, value};
            for (bit_index = 0; bit_index < 32; bit_index = bit_index + 1) begin
                for (digit = 0; digit < 10; digit = digit + 1)
                    if (work_bits[32+digit*4 +: 4] >= 5)
                        work_bits[32+digit*4 +: 4] = work_bits[32+digit*4 +: 4] + 4'd3;
                work_bits = work_bits << 1;
            end
            constant_bcd = work_bits[71:32];
        end
    endfunction
    localparam [39:0] UPDATE_BCD = constant_bcd(UPDATE_US);

    function [7:0] line_char;
        input [5:0] index;
        begin
            line_char = LINE_TEMPLATE[(LINE_BYTES-1-index)*8 +: 8];
            if (index >= 4 && index <= 7)
                line_char = 8'h30 + ((adc_bcd >> ((7-index)*4)) & 4'hf);
            else if (index >= 13 && index <= 16)
                line_char = 8'h30 + ((raw_bcd >> ((16-index)*4)) & 4'hf);
            else if (index == 22) line_char = frame_otr ? "1" : "0";
            else if (index >= 28 && index <= 37)
                line_char = 8'h30 + ((seq_bcd >> ((37-index)*4)) & 4'hf);
            else if (index >= 49 && index <= 54)
                line_char = 8'h30 + ((UPDATE_BCD >> ((54-index)*4)) & 4'hf);
        end
    endfunction

    adc #(.CLK_DIV(ADC_CLK_DIV), .SAMPLE_TICKS(SAMPLE_TICKS), .AVG_LOG2(AVG_LOG2))
        adc_inst (
            .clk(clk),
            .rst_n(rst_n),
            .adc_clk(adc_clk),
            .adc_oe_n(adc_oe_n),
            .adc_stby_n(),
            .adc_otr(adc_otr),
            .adc_data_in(adc_data_in),
            .data(adc_value),
            .data_valid(adc_valid),
            .raw_data(adc_raw),
            .data_otr(adc_over)
        );

    uart_byte_tx
        uart_byte_tx_inst (
            .clk(clk),
            .rst_n(rst_n),
            .data_byte(tx_data),
            .send_en(tx_send),
            .baud_set(3'd4),
            .uart_tx(uart_tx),
            .tx_done(tx_done),
            .uart_state()
        );

    // 十进制转换逐拍处理，避免长组合除法/取模路径。
    integer digit;
    always @(*) begin
        bcd_adjusted = bcd_shift;
        for (digit = 0; digit < 10; digit = digit + 1)
            if (bcd_shift[32+digit*4 +: 4] >= 5)
                bcd_adjusted[32+digit*4 +: 4] = bcd_shift[32+digit*4 +: 4] + 4'd3;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            report_timer <= 0;
            sample_ready <= 0;
            sample_seq <= 0;
        end else begin
            if (report_due) report_timer <= 0;
            else report_timer <= report_next[REPORT_WIDTH-1:0];
            if (adc_valid) begin
                sample_ready <= 1;
                sample_seq <= sample_seq + 1'b1;
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            frame_adc <= 0; frame_raw <= 0; frame_otr <= 0; frame_seq <= 0;
            field_index <= 0; bit_count <= 0; bcd_shift <= 0;
            adc_bcd <= 0; raw_bcd <= 0; seq_bcd <= 0;
            char_index <= 0; tx_data <= 0; tx_send <= 0;
        end else begin
            tx_send <= 0;
            case (state)
                IDLE: begin
                    if (report_due && (sample_ready || adc_valid)) begin
                        frame_adc <= adc_value; frame_raw <= adc_raw;
                        frame_otr <= adc_over;
                        frame_seq <= sample_seq + (adc_valid ? 32'd1 : 32'd0);
                        field_index <= 0;
                        state <= LOAD;
                    end
                end
                LOAD: begin
                    case (field_index)
                        0: bcd_shift <= {40'b0, 20'b0, frame_adc};
                        1: bcd_shift <= {40'b0, 22'b0, frame_raw};
                        default: bcd_shift <= {40'b0, frame_seq};
                    endcase
                    bit_count <= 0;
                    state <= CONVERT;
                end
                CONVERT: begin
                    bcd_shift <= bcd_next;
                    if (bit_count == 31) begin
                        case (field_index)
                            0: adc_bcd <= bcd_next[47:32];
                            1: raw_bcd <= bcd_next[47:32];
                            default: seq_bcd <= bcd_next[71:32];
                        endcase
                        if (field_index == 2) begin
                            char_index <= 0;
                            state <= SEND;
                        end else begin
                            field_index <= field_index + 1'b1;
                            state <= LOAD;
                        end
                    end else bit_count <= bit_count + 1'b1;
                end
                SEND: begin
                    tx_data <= line_char(char_index);
                    tx_send <= 1;
                    state <= WAIT_TX;
                end
                WAIT_TX: begin
                    if (tx_done) begin
                        if (char_index == LINE_BYTES - 1) state <= IDLE;
                        else begin
                            char_index <= char_index + 1'b1;
                            state <= SEND;
                        end
                    end
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
