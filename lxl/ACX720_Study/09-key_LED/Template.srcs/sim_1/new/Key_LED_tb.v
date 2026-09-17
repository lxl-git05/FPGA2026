`timescale 1ns / 1ps
module Key_LED_tb;
    //Ports
    reg  clk;
    reg  rst_n;
    reg [3:0] key_in;
    wire [7:0] LED;

    Key_LED  Key_LED_inst (
        .clk(clk),
        .rst_n(rst_n),
        .key_in(key_in),
        .LED(LED)
    );

    // 时钟
    initial clk = 0 ;
    always #10  clk = ! clk ;

    // 按键与LED交互
    initial 
    begin
        rst_n = 0 ;
        #2_01 ;
        rst_n = 1 ;
        key_in = 4'b1111 ;
        // 开始按下按键
        key_gen(0) ;
        key_gen(0) ;
        key_gen(1) ;
        key_gen(2) ;
        key_gen(3) ;
    end


    // 按键按下事件
    // 按键按下事件
    task key_gen;
        input integer key_num;
        begin
            key_in[key_num] = 1'b1;
            #25_000_000;
            key_in[key_num] = 1'b0;
            #50_000_000;
            key_in[key_num] = 1'b1;
            #25_000_000;
        end
    endtask

endmodule