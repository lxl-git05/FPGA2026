`timescale 1ns / 1ps
module key_tb;
    //Ports
    reg  clk;
    reg  rst_n;
    wire  key_in;
    wire key_state;
    wire key_press;
    wire key_release;
    wire key_change;

    key key_inst (
        .clk(clk),
        .rst_n(rst_n),
        .key_in(key_in),
        .key_state(key_state),
        .key_press(key_press),
        .key_release(key_release),
        .key_change(key_change)
    );

    // 时钟
    initial clk = 0 ;
    always #10  clk = ! clk ;

    // 按键
    reg key_out ;
    reg [15:0] myrand ;

    assign key_in = key_out;

    initial 
    begin
        rst_n = 0 ;
        #201 ;
        rst_n = 1 ;
        // 开始模拟按键
        key_gen ;
        #201 ;
        key_gen ;
        #201 ;
        key_gen ;
    end


    // 按键按下事件
    task key_gen; 
    begin 
        key_out = 1'b1; 
        repeat(50)begin 
        myrand = {$random}%65536;//0~65535; 
        #myrand key_out = ~key_out;            
        end 
        key_out = 0; 
        #25000000; 
        repeat(50)begin 
        myrand = {$random}%65536;//0~65535; 
        #myrand key_out = ~key_out;            
        end 
        key_out = 1; 
        #25000000;  
    end
    endtask
endmodule