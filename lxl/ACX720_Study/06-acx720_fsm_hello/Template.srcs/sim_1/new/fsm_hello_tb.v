`timescale 1ns / 1ps
module fsm_hello_tb;
    `define time_T 20   // 一个时钟周期
    //Ports
    reg  clk;
    reg  rst_n;
    reg [7:0] data_in;
    reg  data_in_valid;
    wire check_ok;

    fsm_hello  fsm_hello_inst (
        .clk(clk),
        .rst_n(rst_n),
        .data_in(data_in),
        .data_in_valid(data_in_valid),
        .check_ok(check_ok)
    );

    // 1. 时钟
    initial clk = 0 ;
    always #10  clk = ! clk ;

    // 2. 逻辑
    initial 
    begin
        // 初始化
        rst_n = 1'b0 ;
        data_in = 8'd0 ;
        data_in_valid = 1'b0 ;
        #21 ;
        rst_n = 1'b1 ;
        // 逻辑
        gen_char_and_delay("h") ;
        gen_char_and_delay("e") ;
        gen_char_and_delay("l") ;
        gen_char_and_delay("o") ;
        gen_char_and_delay("e") ;

        gen_char_and_delay("h") ;
        gen_char_and_delay("e") ;
        gen_char_and_delay("l") ;
        gen_char_and_delay("l") ;
        gen_char_and_delay("o") ;

        gen_char_and_delay("r") ;
        gen_char_and_delay("h") ;
    end

    // 3. 任务: 端口输入一个有效数据char
    task gen_char_and_delay;
        input [7:0] char ;
        begin
            data_in = char ;
            data_in_valid = 1'b1 ;
            #`time_T ;
            data_in_valid = 1'b0 ;
            #(`time_T * 2 + 1) ;       // 加个延时,省的主逻辑又写
        end
    endtask

endmodule