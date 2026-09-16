// 项目: 使用状态机实现hello语句检测
`timescale 1ns / 1ps
module fsm_hello(
        input wire clk,
        input wire rst_n,
        input wire [7:0] data_in,  // 输入数据 
        input wire data_in_valid,  // 输入数据有效(正在输入数据)
        output reg check_ok        // 检测到正确语句
    );

    // 永远不可被更改的,可以看成#define
    localparam CHECK_h  = 5'b00001 ;
    localparam CHECK_e  = 5'b00010 ;
    localparam CHECK_l1 = 5'b00100 ;
    localparam CHECK_l2 = 5'b01000 ;
    localparam CHECK_o  = 5'b10000 ;
    reg [4:0] state ;

    // 状态机
    always@(posedge clk or negedge rst_n) 
    begin
        if(!rst_n) 
        begin
            state <= CHECK_h ;
            check_ok <= 1'b0 ;
        end
        else if (data_in_valid) 
        begin
            case (state)
                CHECK_h : 
                begin
                    check_ok <= 1'b0 ;
                    if (data_in == "h")
                        state <= CHECK_e ;
                    else
                        state <= CHECK_h ;
                end
                CHECK_e : 
                begin
                    check_ok <= 1'b0 ;
                    if (data_in == "h")
                        state <= CHECK_e ;
                    else if (data_in == "e")
                        state <= CHECK_l1 ;
                    else
                        state <= CHECK_h ;
                end
                CHECK_l1 : 
                begin
                    check_ok <= 1'b0 ;
                    if (data_in == "h")
                        state <= CHECK_e ;
                    else if (data_in == "l")
                        state <= CHECK_l2 ;
                    else
                        state <= CHECK_h ;
                end
                CHECK_l2 : 
                begin
                    check_ok <= 1'b0 ;
                    if (data_in == "h")
                        state <= CHECK_e ;
                    else if (data_in == "l")
                        state <= CHECK_o ;
                    else
                        state <= CHECK_h ;
                end
                CHECK_o : 
                begin
                    check_ok <= 1'b0 ;
                    if (data_in == "o")
                    begin
                        state <= CHECK_h ;
                        check_ok <= 1'b1 ;
                    end
                    else if (data_in == "h")
                        state <= CHECK_e ;
                    else begin
                        state <= CHECK_h ;
                        check_ok <= 1'b0 ;
                    end
                end
                default:state <= CHECK_h; 
            endcase
        end
        else 
        begin
            state <= state ;
        end
    end
endmodule
