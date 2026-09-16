// 项目: 串口发送单个字符(Byte)
`timescale 1ns / 1ps
module uart_byte_tx(
        input wire clk,
        input wire rst_n,

        input wire [2:0] baud_set,      // 波特率选择
        input wire [7:0] data_byte,     // 需要Tx的信息
        input wire send_en,             // 串口使能信号

        output wire uart_tx,             // 串口输出口
        output wire tx_done,             // 输出完成信号
        output wire uart_state           // TX端口状态
    );

    // 进行例化
    // 1. 串口选择
    wire [15:0] bps_DR ;
    DR_LUT  DR_LUT_inst (
        .clk(clk),
        .rst_n(rst_n),
        .baud_set(baud_set),
        .bps_DR(bps_DR)
    );
    // 2. 波特率时钟输出
    wire bps_clk ;
    div_cnt  div_cnt_inst (
        .clk(clk),
        .rst_n(rst_n),
        .uart_state(uart_state),
        .bps_DR(bps_DR),
        .bps_clk(bps_clk)
    );
    // 3. 波特率周期计数
    wire [3:0] bps_cnt ;
    bps_cnt  bps_cnt_inst (
        .clk(clk),
        .rst_n(rst_n),
        .bps_clk(bps_clk),
        .bps_cnt(bps_cnt)
    );
    // 4. 输出完成标志位
    tx_done_reg  tx_done_reg_inst (
        .clk(clk),
        .rst_n(rst_n),
        .bps_cnt(bps_cnt),
        .tx_done(tx_done)
    );
    // 5. 串口TX状态标志位
    uart_state_reg  uart_state_reg_inst (
        .clk(clk),
        .rst_n(rst_n),
        .bps_cnt(bps_cnt),
        .send_en(send_en),
        .uart_state(uart_state)
    );
    // 6. TX数据锁存器
    wire [7:0] data_byte_reg ;
    data_reg  data_reg_inst (
        .clk(clk),
        .rst_n(rst_n),
        .send_en(send_en),
        .data_byte(data_byte),
        .data_byte_reg(data_byte_reg)
    );
    // 7. 串口输出端口
    mux_tx # 
    (
        .START_BIT(0),
        .STOP_BIT(1)
    )
    mux_tx_inst (
        .clk(clk),
        .rst_n(rst_n),
        .bps_cnt(bps_cnt),
        .data_byte_reg(data_byte_reg),
        .uart_tx(uart_tx)
    );
endmodule

// 1. 波特率查表器
`timescale 1ns / 1ps
module DR_LUT(
        input  wire clk,
        input  wire rst_n,
        input  wire [2:0]  baud_set,
        output reg  [15:0] bps_DR
    );
    // 波特率选择
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            bps_DR <= 16'd5207;
        else 
            case (baud_set)
                0 : bps_DR <= 16'd5207; // 9600bps/s
                1 : bps_DR <= 16'd2603;
                2 : bps_DR <= 16'd1301;
                3 : bps_DR <= 16'd867 ;
                4 : bps_DR <= 16'd433 ;
                default: bps_DR <= 16'd5207;
            endcase
    end
endmodule

// 2. 波特率时钟输出
`timescale 1ns / 1ps
module div_cnt(
        input wire clk,
        input wire rst_n,
        input wire uart_state,
        input wire [15:0]bps_DR,
        output reg bps_clk
    );
    // 2.1 内部计时器
    reg [15:0] div_cnt ;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            div_cnt <= 16'd0;
        else if (uart_state) begin
            if (div_cnt == bps_DR)
                div_cnt <= 16'd0 ;
            else
                div_cnt <= div_cnt + 1'b1 ;
        end
    end

    // 2.2 波特率时钟输出
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            bps_clk <= 1'b0;
        else if (uart_state) begin
            if (div_cnt == bps_DR)
                bps_clk <= 1'b1 ;
            else
                bps_clk <= 1'b0 ;
        end
    end
endmodule

// 3. 波特率计数器: bit_cnt = 0,1,2,...,11,0
`timescale 1ns / 1ps
module bps_cnt(
        input wire clk,
        input wire rst_n,
        input wire bps_clk,
        output reg [3:0]bps_cnt // 0-11
    );
    // 根据波特率时钟bps_clk产生cnt,clk纯粹是计数器激活always用的
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            bps_cnt <= 4'b0 ;
        else if (bps_clk) // 注意: 这里是波特率clk才能cnt++,并且由于bps_clk是在clk上升沿到达bps_DR,而此时clk上升沿结束，所以bps_cnt只能等到下一次clk才能++
            bps_cnt <= bps_cnt + 1'b1 ;
        else if (bps_cnt == 4'd11)
            bps_cnt <= 4'b0 ;
        else
            bps_cnt <= bps_cnt ;
    end
endmodule

// 4. 一次TX输出完成标志
`timescale 1ns / 1ps
module tx_done_reg(
        input wire clk,
        input wire rst_n,
        input wire [3:0] bps_cnt,
        output reg tx_done
    );
    // 判断输出是否完成
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            tx_done <= 1'b0 ;
        else if (bps_cnt == 4'd11) // bps_cnt在11计数值的时候会在下一个clk立即变成0,而不是等到下一个bps_clk
            tx_done <= 1'b1 ;
        else
            tx_done <= 1'b0 ;
    end
endmodule

// 5. 串口TX忙标志位,忙的时候是1,空闲的时候是0
`timescale 1ns / 1ps
module uart_state_reg(
        input wire clk,
        input wire rst_n,
        input wire [3:0] bps_cnt,
        input wire send_en,
        output reg uart_state   // 忙的时候是1
    );
    // 忙的时候是1
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            uart_state <= 1'b0 ;
        else if (send_en == 1'b1)   // send_en也只是一个周期就重新变成0
            uart_state <= 1'b1 ;
        else if (bps_cnt == 4'd11)  // 工作状态结束,等待下一个send_en尖峰
            uart_state <= 1'b0 ;
        else
            uart_state <= uart_state ;
    end
endmodule

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

// 6. 10路选择器发送Tx_Data
`timescale 1ns / 1ps
module mux_tx
    #(
        parameter integer START_BIT = 0 ,
        parameter integer  STOP_BIT = 1 
    )
    (
        input wire clk,
        input wire rst_n,
        input wire [3:0] bps_cnt,
        input wire [7:0] data_byte_reg,
        output reg uart_tx  // 每个 波特率周期clk 只发送一位
    );

    // 10路选择与发送
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            uart_tx <= 1'b1 ;   // 空闲的时候是1
        else 
        begin
            case (bps_cnt)
                0 : uart_tx <= 1'b1 ;   // 空闲位(我在想有没有必要?)
                1 : uart_tx <= START_BIT ;
                2 : uart_tx <= data_byte_reg[0] ;   // LSB顺序,所以是从低位开始
                3 : uart_tx <= data_byte_reg[1] ;
                4 : uart_tx <= data_byte_reg[2] ;
                5 : uart_tx <= data_byte_reg[3] ;
                6 : uart_tx <= data_byte_reg[4] ;
                7 : uart_tx <= data_byte_reg[5] ;
                8 : uart_tx <= data_byte_reg[6] ;
                9 : uart_tx <= data_byte_reg[7] ;
                10: uart_tx <= STOP_BIT ;
                default : uart_tx <= 1'b1 ;
            endcase
        end
        
    end
endmodule

