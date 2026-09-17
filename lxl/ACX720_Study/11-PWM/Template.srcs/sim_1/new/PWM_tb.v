`timescale 1ns / 1ps
module PWM_tb;
    reg  clk;
    reg  rst_n;
    reg  pwm_gen_en;
    reg [31:0] counter_arr;
    reg [31:0] counter_ccr;
    wire pwm_out;

    PWM  PWM_inst (
        .clk(clk),
        .rst_n(rst_n),
        .pwm_gen_en(pwm_gen_en),
        .counter_arr(counter_arr),
        .counter_ccr(counter_ccr),
        .pwm_out(pwm_out)
    );

    initial clk = 0 ;
    always #10  clk = ! clk ;

    // 逻辑
    initial 
    begin
        rst_n = 0 ;
        pwm_gen_en = 1 ;
        counter_arr = 32'd1000 ;
        counter_ccr = 32'd400  ;
        // 开始
        # 201 rst_n = 1 ;
        # 20_000_000 counter_arr = 10000 ;
        # 20_000_000 counter_ccr = 6000  ;
    end

endmodule