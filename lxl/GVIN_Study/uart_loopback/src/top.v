// 工程：J280按键字符串发送与UART原样回传，50MHz，SW5低有效复位。
// 模块：key消抖模块×3、uart_byte_rx、uart_byte_tx；UART为115200/8N1。
// 业务：松开SW1发送hello，松开SW2发送world，松开SW3发送666，不附加换行。
// 接收到的每个字节原样回传，包括二进制字节；复位清除待发送内容，TX回到空闲高。
// 发送事件按到达顺序缓存；同拍先回传接收字节，再按SW1~SW3顺序发送完整字符串。
// 当前字符串发送期间不插入其它内容；缓存256个事件，满时丢弃最新事件。
`timescale 1ns / 1ps
module top (
    input wire clk,
    input wire rst_n,
    input wire [2:0] key_in,
    input wire uart_rx,
    output wire uart_tx
);
    localparam [2:0] IDLE = 3'd0,
                     SELECT_KEY = 3'd1,
                     SEND_TEXT = 3'd2,
                     WAIT_TEXT = 3'd3,
                     WAIT_ECHO = 3'd4;

    wire [2:0] key_release;
    wire [7:0] rx_data;
    wire rx_done, tx_done;
    reg [7:0] tx_data;
    reg tx_send;
    reg [2:0] state;
    reg [2:0] pending_keys;
    reg [39:0] text_data;
    reg [2:0] text_left;

    // 每个事件保存同拍的RX字节有效位、三个松开事件和RX数据。
    reg [11:0] event_fifo [0:255];
    reg [7:0] write_ptr, read_ptr;
    reg [8:0] event_count;
    wire event_in = rx_done || (|key_release);
    wire pop_event = (state == IDLE) && (event_count != 0);
    wire push_event = event_in && ((event_count < 9'd256) || pop_event);

    genvar i;
    generate
        for (i = 0; i < 3; i = i + 1) begin : gen_keys
            key #(.KEY_UNPRESSED(1'b1))
                key_inst (
                    .clk(clk),
                    .rst_n(rst_n),
                    .key_in(key_in[i]),
                    .key_state(),
                    .key_press(),
                    .key_release(key_release[i]),
                    .key_change()
                );
        end
    endgenerate

    uart_byte_rx
        uart_byte_rx_inst (
            .clk(clk),
            .rst_n(rst_n),
            .baud_set(3'd4),
            .uart_rx(uart_rx),
            .data_byte(rx_data),
            .rx_Done(rx_done)
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

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            write_ptr <= 0;
            read_ptr <= 0;
            event_count <= 0;
        end else begin
            if (push_event) begin
                event_fifo[write_ptr] <= {rx_done, key_release, rx_data};
                write_ptr <= write_ptr + 1'b1;
            end
            if (pop_event) read_ptr <= read_ptr + 1'b1;
            case ({push_event, pop_event})
                2'b10: event_count <= event_count + 1'b1;
                2'b01: event_count <= event_count - 1'b1;
                default: ;
            endcase
        end
    end

    // TX完成握手后才启动下一字节，字符串在一次事件内连续发送。
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            pending_keys <= 0;
            text_data <= 0;
            text_left <= 0;
            tx_data <= 0;
            tx_send <= 0;
        end else begin
            tx_send <= 0;
            case (state)
                IDLE: begin
                    if (pop_event) begin
                        pending_keys <= event_fifo[read_ptr][10:8];
                        if (event_fifo[read_ptr][11]) begin
                            tx_data <= event_fifo[read_ptr][7:0];
                            tx_send <= 1;
                            state <= WAIT_ECHO;
                        end else state <= SELECT_KEY;
                    end
                end
                SELECT_KEY: begin
                    if (pending_keys[0]) begin
                        pending_keys[0] <= 0;
                        text_data <= "hello";
                        text_left <= 5;
                        state <= SEND_TEXT;
                    end else if (pending_keys[1]) begin
                        pending_keys[1] <= 0;
                        text_data <= "world";
                        text_left <= 5;
                        state <= SEND_TEXT;
                    end else if (pending_keys[2]) begin
                        pending_keys[2] <= 0;
                        text_data <= {"666", 16'b0};
                        text_left <= 3;
                        state <= SEND_TEXT;
                    end else state <= IDLE;
                end
                SEND_TEXT: begin
                    tx_data <= text_data[39:32];
                    text_data <= text_data << 8;
                    text_left <= text_left - 1'b1;
                    tx_send <= 1;
                    state <= WAIT_TEXT;
                end
                WAIT_TEXT: begin
                    if (tx_done)
                        state <= (text_left == 0) ? SELECT_KEY : SEND_TEXT;
                end
                WAIT_ECHO: begin
                    if (tx_done) state <= SELECT_KEY;
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
