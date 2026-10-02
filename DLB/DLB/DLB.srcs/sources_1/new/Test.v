// 测试文件
`timescale 1ns / 1ps
module Test(
    input wire clk,
    input wire rst_n,
    input wire [3:0] key_in,
    output wire uart_tx,
    output wire ds,
    output wire sh_cp,
    output wire st_cp

    );
    reg [31:0] Data;
    reg [1:0] radix;
    reg tx_busy;
    wire [2:0] key_release;
    wire tx_done;
    wire send_en = key_release[0] && !tx_busy;

    genvar i;
    generate for (i = 0; i < 3; i = i + 1) begin : keys
        key u_key (.clk(clk), .rst_n(rst_n), .key_in(key_in[i]),
                   .key_release(key_release[i]));
    end endgenerate

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            Data <= 32'd220;
            radix <= 2'd1;
            tx_busy <= 1'b0;
        end else begin
            if (key_release[1]) Data <= Data + 32'd20;
            if (key_release[2]) radix <= radix + 2'd1; // 01 -> 10 -> 11(熄屏) -> 00
            if (send_en) tx_busy <= 1'b1;
            else if (tx_done) tx_busy <= 1'b0;
        end
    end

    // 115200 baud，发送4个原始字节，高字节在前；发送期间忽略重复请求。
    uart_data_tx #(.DATA_WIDTH(32), .MSB_FIRST(1)) u_uart (
        .clk(clk), .rst_n(rst_n), .data(Data), .send_en(send_en),
        .Baud_Set(3'd4), .uart_tx(uart_tx), .Tx_Done(tx_done));
    Seg8 u_seg (.clk(clk), .reset_n(rst_n), .data(Data), .format(radix),
                .ds(ds), .sh_cp(sh_cp), .st_cp(st_cp));
endmodule
