// 项目: PWM(驱动蜂鸣器)
/*
    频率 = 50MHz / counter_arr
    占空比 = counter_ccr / counter_arr ;    // 占空比越大,LED越亮
*/
`timescale 1ns / 1ps
module PWM(
        input wire clk ,
        input wire rst_n  ,
        input wire pwm_gen_en ,
        input wire [31:0] counter_arr ,     // 32位预重装值,确定频率(50M / counter_arr)
        input wire [31:0] counter_ccr ,     // 32位输出比较值,确定占空比
        output reg pwm_out                  // PWM输出
    );

    // 1. 定时器实现时钟频率计数
    reg [31:0] pwm_gen_cnt ;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            pwm_gen_cnt <= 32'd1 ;
        end
        else if (pwm_gen_en) begin
            if (pwm_gen_cnt <= 32'd1)
                pwm_gen_cnt <= counter_arr ;    // 计数减到1,加载预重装载寄存器
            else begin
                pwm_gen_cnt <= pwm_gen_cnt - 1'b1 ;
            end
        end
        else begin
            pwm_gen_cnt <= counter_arr ;        // 未使能
        end
    end

    // 2. 输出PWM
    always@(posedge clk or negedge rst_n) begin
        if(!rst_n) 
            pwm_out <= 1'b0; 
        else if(pwm_gen_cnt <= counter_ccr) // 计数值小于比较值，PWM输出高电平 
            pwm_out <= 1'b1; 
        else 
            pwm_out <= 1'b0;                // 计数值大于比较值，PWM输出低电平
    end
endmodule
