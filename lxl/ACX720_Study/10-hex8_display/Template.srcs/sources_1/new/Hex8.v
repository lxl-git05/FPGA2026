// 项目: 8 * 八段数码管显示数据
`timescale 1ns / 1ps
module Hex8(
        input wire clk ,
        input wire rst_n ,
        input wire disp_en ,
        input wire [31:0] disp_data ,
        output reg [7:0] sel ,          // 位选
        output reg [7:0] seg            // 段选
    );
    
    // 8位控制计数
    reg [2:0] seg_ctrl_cnt ;

    // 1. 时钟分频(1ms)
    reg [14:0] seg_cnt ;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) 
            seg_cnt <= 15'd0;
        else if (seg_cnt >= 15'd24_999)    // 1ms 
            seg_cnt <= 15'd0 ;
        else 
            seg_cnt <= seg_cnt + 1'b1 ;
    end

    // 2. seg_ctrl_cnt 选择 (直接自增直到溢出)
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) 
            seg_ctrl_cnt <= 3'd0;
        else if (seg_cnt >= 15'd24_999)    // 1ms 
            seg_ctrl_cnt <= seg_ctrl_cnt + 1'b1 ;
        else 
            seg_ctrl_cnt <= seg_ctrl_cnt ;
    end

    // 3. 位选
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) 
            sel <= 8'd0;
        else begin
            sel <= 8'b0000_0001 << seg_ctrl_cnt ;
        end
    end

    // 4. 段选
    reg [3:0] data_temp ;   // 即将显示的1Byte
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) 
            data_temp <= 8'd0;
        else begin
            case (seg_ctrl_cnt)
                0 : data_temp <= disp_data[ 3: 0] ;
                1 : data_temp <= disp_data[ 7: 4] ;
                2 : data_temp <= disp_data[11: 8] ;
                3 : data_temp <= disp_data[15:12] ;
                4 : data_temp <= disp_data[19:16] ;
                5 : data_temp <= disp_data[23:20] ;
                6 : data_temp <= disp_data[27:24] ;
                7 : data_temp <= disp_data[31:28] ;
            endcase
        end
    end

    always@(*) 
    case(data_temp) 
        4'h0:seg = 7'b1000000; 
        4'h1:seg = 7'b1111001; 
        4'h2:seg = 7'b0100100; 
        4'h3:seg = 7'b0110000; 
        4'h4:seg = 7'b0011001; 
        4'h5:seg = 7'b0010010; 
        4'h6:seg = 7'b0000010; 
        4'h7:seg = 7'b1111000; 
        4'h8:seg = 7'b0000000; 
        4'h9:seg = 7'b0010000; 
        4'ha:seg = 7'b0001000; 
        4'hb:seg = 7'b0000011; 
        4'hc:seg = 7'b1000110; 
        4'hd:seg = 7'b0100001; 
        4'he:seg = 7'b0000110; 
        4'hf:seg = 7'b0001110; 
    endcase 

endmodule
