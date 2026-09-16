// 使用vio进行实验
`timescale 1ns / 1ps
module fsm_hello_test(
        input wire clk,
        input wire rst_n,
        output wire check_ok        // 检测到正确语句,这里使用wire是因为没有用在always,那么只能算是连线
    );
    // 输入数据
    reg [7:0] data_in;  // 输入数据
    reg data_in_valid;  // 输入数据有效(正在输入数据)
    // vio控制的数据
    wire       Key;
    wire [7:0] data_PC_in;

    // 例化
    fsm_hello  fsm_hello_inst (
        .clk(clk),
        .rst_n(rst_n),
        .data_in(data_in),
        .data_in_valid(data_in_valid),
        .check_ok(check_ok)
    );

    // 加入VIO调试
    //----------- Begin Cut here for INSTANTIATION Template ---// INST_TAG
    vio_0 your_instance_name (
        .clk(clk),                // input wire clk
        .probe_out0(Key),  // output wire [0 : 0] probe_out0
        .probe_out1(data_PC_in)   // output wire [7 : 0] probe_out1
    );

    // probe_out0模拟按键,使用按键上升沿检测(也就是一般为0,按下为1)
    reg  Key_reg1 ;
    reg  Key_reg2 ;
    wire Key_posedge ;
    // 时刻进行检测
    always@(posedge clk or negedge rst_n) 
    begin
        if(!rst_n) begin
            Key_reg1 <= 1'b0 ;
            Key_reg2 <= 1'b0 ;
        end
        else begin
            Key_reg1 <= Key ;
            Key_reg2 <= Key_reg1 ;
        end
    end

    // 上升沿检测(每次按下按键只有1个clk周期有效,符合输入数据valid的单周期有效性)
    assign Key_posedge = (Key_reg1 && !Key_reg2);

    // 按键上升沿发送一次数据
    always@(posedge clk or negedge rst_n) 
    begin
        if(!rst_n) begin
            data_in <= 8'd0 ;
            data_in_valid <= 1'b0 ;
        end
        else if (Key_posedge) begin
            data_in_valid <= 1'b1 ;
            data_in <= data_PC_in ;
        end
        else begin
            data_in_valid <= 1'b0 ;
        end
    end

endmodule
