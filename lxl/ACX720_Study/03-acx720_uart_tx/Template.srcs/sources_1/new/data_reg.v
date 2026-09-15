// 5. 数据寄存器,防止在TX的时候数据源更改导致data错误
`timescale 1ns / 1ps
module data_reg(
        input wire clk,
        input wire rst_n,
        input wire send_en,
        input wire [7:0] data_byte,
        output reg [7:0] data_byte_reg
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            data_byte_reg <= 8'd0 ;
        else if (send_en == 1'b1)
            data_byte_reg <= data_byte ;    // send_en尖峰过去之后就是数据锁存,下一次send_en出现才能更新Tx数据
        else    
            data_byte_reg <= data_byte_reg ;    // 数据锁存
    end
endmodule
