`timescale 1ns / 1ps
// K1 toggles running. Real faults latch until conditions clear and a NEW K1 press occurs.
// 新增起摆失败自动重启（只在已经进入BALANCE后有效）：
//   1) 角度快照离开稳摆区(fall_adc)，或位置计数变化速度超过FALL_SPEED_CPS，
//      立即软复位：退出BALANCE、PID失能清零、电机断使能、位置原点重设，进入RECOVER；
//   2) RECOVER中角度回到回中区中心RESTART_CENTER_ADC±RESTART_ADC并连续保持
//      RESTART_CONFIRM_MS后，自动进入AUTO_SWING重新起摆；若复位瞬间角度仍在
//      回中区内，必须先离开再回中；
//   3) K1按键优先于自动恢复；传感器失效、行程越界、起摆超时仍锁存FAULT，不自动重启。
// 速度窗口：|Δposition_count| >= FALL_SPEED_CPS*FALL_SPEED_WINDOW_MS/1000 判为过快。
// 1040 counts = 360°，默认1040 counts/s，即1圈/s。
// 回中区：12位无符号角度在0/4096处回绕，RESTART_CENTER_ADC默认0，
//         窗口为0±RESTART_ADC，即0..RESTART_ADC与4096-RESTART_ADC..4095。
module run_control #(
    parameter integer RESTART_ADC=100,          // 回中区半宽，ADC码
    parameter integer RESTART_CENTER_ADC=0,     // 回中区中心，ADC码；0=零点
    parameter integer RESTART_CONFIRM_MS=500,     // 回中连续确认时间，ms
    parameter integer FALL_SPEED_CPS=1040,      // 位置变化速度上限，counts/s
    parameter integer FALL_SPEED_WINDOW_MS=1000   // 测速窗口，ms
)(input wire clk,rst_n,ms_tick,key_press,sensor_ok,position_safe,config_ready,
    input wire auto_start,fault_now,capture_request,swing_timed_out,
    input wire [3:0] fault_reason,
    input wire signed [31:0] encoder_count,pid_pwm_ticks,swing_pwm_ticks,
    input wire signed [31:0] position_count,
    input wire [11:0] angle_adc,
    input wire angle_valid,
    output reg [2:0] state, output reg [3:0] fault_code,
    output reg signed [31:0] position_origin,
    output reg capture_clear,
    output wire active,balancing,swing_enable,motor_enable,
    output wire signed [31:0] motor_pwm_ticks);
    localparam STOPPED=0,MANUAL_WAIT=1,AUTO_SWING=2,BALANCE=3,FAULT=4,RECOVER=5;
    localparam integer SPEED_WINDOW=(FALL_SPEED_WINDOW_MS<1)?1:FALL_SPEED_WINDOW_MS;
    localparam integer SPEED_LIMIT_RAW=(FALL_SPEED_CPS*SPEED_WINDOW+999)/1000;
    localparam integer SPEED_LIMIT=(SPEED_LIMIT_RAW<1)?1:SPEED_LIMIT_RAW;
    localparam integer CONFIRM=(RESTART_CONFIRM_MS<1)?1:RESTART_CONFIRM_MS;
    localparam integer RETURN_ADC=(RESTART_ADC<0)?0:RESTART_ADC;
    localparam integer RETURN_CENTER=(RESTART_CENTER_ADC<0)?0:
                                     (RESTART_CENTER_ADC>4095)?4095:RESTART_CENTER_ADC;
    assign active=(state==MANUAL_WAIT)||(state==AUTO_SWING)||(state==BALANCE)||(state==RECOVER);
    assign balancing=(state==BALANCE);
    assign swing_enable=(state==MANUAL_WAIT)||(state==AUTO_SWING);
    // RECOVER/MANUAL_WAIT不需要驱动电机，motor_en=0与0%占空比在TB6612上都表现为滑行。
    assign motor_enable=((state==AUTO_SWING)||(state==BALANCE))&&
                        sensor_ok&&!fault_now&&!swing_timed_out&&!key_press;
    assign motor_pwm_ticks=!motor_enable?32'sd0:
                           (state==AUTO_SWING)?swing_pwm_ticks:
                           (state==BALANCE)?pid_pwm_ticks:32'sd0;

    // ---------------- 位置变化速度测量 ----------------
    reg [15:0] speed_ms;
    reg signed [31:0] speed_prev;
    reg speed_fault;
    wire signed [32:0] position_ext={position_count[31],position_count};
    wire signed [32:0] speed_delta=position_ext-{speed_prev[31],speed_prev};
    wire [32:0] speed_abs=speed_delta[32]?-speed_delta:speed_delta;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin speed_ms<=0; speed_prev<=0; speed_fault<=0; end
        else begin
            speed_fault<=0;
            if(!balancing) begin
                speed_ms<=0;
                speed_prev<=position_count; // 进入稳摆前持续跟随，首窗从入稳摆位置起算
            end else if(ms_tick) begin
                if(speed_ms>=SPEED_WINDOW-1) begin
                    speed_ms<=0;
                    speed_prev<=position_count;
                    if(speed_abs>=SPEED_LIMIT) speed_fault<=1;
                end else speed_ms<=speed_ms+1'b1;
            end
        end
    end

    // ---------------- 回中检测 ----------------
    reg [15:0] near_ms;
    reg left_window;
    // 12位无符号角度是圆周量：0和4095相邻。先算普通差值，再把超过半圈的
    // 结果折回[-2048,2047]，得到绕4096的最短距离。中心0时4090会算成-6。
    wire signed [12:0] return_raw=
        $signed({1'b0,angle_adc})-$signed({1'b0,RETURN_CENTER[11:0]});
    wire signed [12:0] return_error=
        (return_raw>13'sd2048)?return_raw-13'sd4096:
        (return_raw< -13'sd2048)?return_raw+13'sd4096:return_raw;
    wire [12:0] return_abs=return_error[12]?-return_error:return_error;
    wire near_center=sensor_ok&&angle_valid&&(return_abs<=RETURN_ADC);
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) near_ms<=0;
        else if((state!=RECOVER)||!left_window||!near_center) near_ms<=0;
        else if(ms_tick&&(near_ms<CONFIRM-1)) near_ms<=near_ms+1'b1;
    end
    wire restart_ready=(state==RECOVER)&&left_window&&near_center&&(near_ms>=CONFIRM-1);

    // fault_reason=4 是cascade_control用5ms内环快照算出的稳摆区越界，只脉冲一拍。
    // 把它从“锁存FAULT”改成“可恢复的落摆”；其余故障仍走FAULT。
    wire balance_fall=balancing&&(fault_reason==4'd4);
    wire recover_now=balance_fall||(balancing&&speed_fault);

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=STOPPED; fault_code<=0; position_origin<=0; capture_clear<=0; left_window<=0;
        end else begin
            capture_clear<=0;
            if(active&&(swing_timed_out||(fault_now&&!balance_fall))) begin
                state<=FAULT; fault_code<=swing_timed_out?4'd5:fault_reason; left_window<=0;
            end else if(key_press) begin
                if(active) begin state<=STOPPED; left_window<=0; end
                else if(sensor_ok&&position_safe&&config_ready) begin
                    position_origin<=encoder_count; fault_code<=0; left_window<=0;
                    state<=auto_start?AUTO_SWING:MANUAL_WAIT;
                end
            end else if(recover_now) begin
                // 软复位：下一拍balancing=0，cascade_control/PID_Core自动清积分，motor_enable关断
                state<=RECOVER;
                fault_code<=0;
                capture_clear<=1;
                position_origin<=encoder_count; // 行程限幅与位置环从落摆点重新起算
                left_window<=!near_center;     // 复位瞬间还在回中区内则要求先离开
            end else if(state==RECOVER) begin
                if(!near_center) left_window<=1;
                if(restart_ready) begin
                    state<=AUTO_SWING;
                    capture_clear<=1;
                    position_origin<=encoder_count;
                    left_window<=0;
                end
            end else begin
                left_window<=0;
                if(swing_enable&&capture_request) begin
                    state<=BALANCE; capture_clear<=1;
                end
            end
        end
    end
endmodule
