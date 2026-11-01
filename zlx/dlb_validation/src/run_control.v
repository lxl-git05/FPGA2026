`timescale 1ns / 1ps
// K1 toggles running. Overspeed(6)/fallen(4)/swing-timeout auto-reset and re-swing;
// ADC(1/2) and position-rail(3) faults latch until a new K1 press.
// Auto re-swing: after all checks pass on a fresh 100ms window -
// angle_adc in 0..100 for 5 consecutive windows (500ms, down_cnt>=5),
// encoder nearly still (|delta|<=2 counts/100ms),
// angle still (|delta|<=4 codes/100ms, low pendulum speed) -
// an extra 500ms settle delay runs (aborted if any condition degrades), then re-swing.
// Auto re-swing keeps the ORIGINAL position_origin from the first K1 launch.
module run_control(input wire clk,rst_n,key_press,sensor_ok,position_safe,config_ready,
    input wire ms_tick,
    input wire auto_start,fault_now,capture_request,swing_timed_out,
    input wire [3:0] fault_reason,
    input wire [11:0] angle_adc,
    input wire signed [31:0] encoder_count,pid_pwm_ticks,swing_pwm_ticks,
    output reg [2:0] state, output reg [3:0] fault_code,
    output reg signed [31:0] position_origin,
    output reg capture_clear,
    output reg auto_retry,   // 1: this run came from an automatic re-swing (return-to-goal logic applies)
    output wire active,balancing,swing_enable,motor_enable,
    output wire signed [31:0] motor_pwm_ticks);
    localparam STOPPED=0,MANUAL_WAIT=1,AUTO_SWING=2,BALANCE=3,FAULT=4;
    // Auto-retry faults restart swinging automatically: swing timeout(5), fallen(4), overspeed(6).
    // ADC faults(1/2) and position rail(3) stay latched and need a new K1 press.
    reg auto_restart;
    // Pendulum is hanging down: angle_adc within 0..100 only.
    wire pendulum_down=(angle_adc<=12'd100);
    // ---- near-zero encoder speed detection: 100ms sliding window ----
    localparam integer STILL_THRESHOLD=2;   // counts per 100ms (~20 counts/s, well below 1040)
    localparam integer ANGLE_STILL_THRESHOLD=4;   // ADC codes per 100ms window
    reg [6:0] speed_cnt;
    reg signed [32:0] enc_prev;
    reg position_still;
    reg [11:0] angle_prev;
    reg angle_still;
    reg [2:0] down_cnt;   // consecutive 100ms windows with pendulum_down (0..5)
    reg settling;         // 500ms extra delay after all checks pass
    reg [9:0] settle_ms;
    wire signed [33:0] enc_delta={{2{encoder_count[31]}},encoder_count}-{enc_prev[32],enc_prev};
    wire signed [12:0] angle_delta=$signed({1'b0,angle_adc})-$signed({1'b0,angle_prev});
    assign active=(state==MANUAL_WAIT)||(state==AUTO_SWING)||(state==BALANCE);
    assign balancing=(state==BALANCE);
    assign swing_enable=(state==MANUAL_WAIT)||(state==AUTO_SWING);
    assign motor_enable=active&&sensor_ok&&!fault_now&&!swing_timed_out&&!key_press;
    assign motor_pwm_ticks=!motor_enable?32'sd0:
                           (state==AUTO_SWING)?swing_pwm_ticks:
                           (state==BALANCE)?pid_pwm_ticks:32'sd0;
    // near-zero encoder speed and angle stillness, evaluated every 100ms (runs continuously)
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin speed_cnt<=0; enc_prev<=0; position_still<=0; angle_prev<=0; angle_still<=0; down_cnt<=0; end
        else if(ms_tick) begin
            if(speed_cnt==99) begin
                speed_cnt<=0;
                position_still<=(enc_delta<=STILL_THRESHOLD)&&(enc_delta>= -STILL_THRESHOLD);
                angle_still<=(angle_delta<=ANGLE_STILL_THRESHOLD)&&(angle_delta>= -ANGLE_STILL_THRESHOLD);
                enc_prev<={encoder_count[31],encoder_count};
                angle_prev<=angle_adc;
                // consecutive pendulum-down windows: 5 in a row (500ms, 0..100 only)
                if(pendulum_down) down_cnt<=(down_cnt==5)?down_cnt:down_cnt+1'b1;
                else down_cnt<=0;
            end else speed_cnt<=speed_cnt+1'b1;
        end
    end
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin state<=STOPPED; fault_code<=0; position_origin<=0; capture_clear<=0;
                      auto_restart<=0; settling<=0; settle_ms<=0; auto_retry<=0; end
        else begin
            capture_clear<=0;
            if(key_press) begin
                auto_restart<=0; settling<=0; auto_retry<=0;   // first launch: original behavior
                if(active) state<=STOPPED;
                else if(sensor_ok&&position_safe&&config_ready) begin
                    position_origin<=encoder_count; fault_code<=0;
                    state<=auto_start?AUTO_SWING:MANUAL_WAIT;
                end
            end else if(active&&fault_now&&fault_reason!=4'd4&&fault_reason!=4'd6) begin
                state<=FAULT; fault_code<=fault_reason;   // ADC/position faults latch
            end else if(active&&(swing_timed_out||fault_now)) begin
                state<=STOPPED;                            // timeout/fallen/overspeed -> reset
                fault_code<=swing_timed_out?4'd5:fault_reason;
                auto_restart<=1; settling<=0; settle_ms<=0;
            end else if(auto_restart) begin
                if(settling) begin
                    // 500ms extra delay; abort back to waiting if any condition degrades
                    if(ms_tick) begin
                        if(sensor_ok&&position_safe&&config_ready&&(down_cnt>=5)&&position_still&&angle_still) begin
                            if(settle_ms>1) settle_ms<=settle_ms-1'b1;
                            else begin
                                // keep the ORIGINAL position_origin from the first K1 launch,
                                // so the cart returns to the first swing-up position
                                settling<=0; auto_restart<=0;
                                auto_retry<=1;     // automatic re-swing: enable return logic
                                fault_code<=0;
                                state<=auto_start?AUTO_SWING:MANUAL_WAIT;
                            end
                        end else settling<=0;
                    end
                end else begin
                    // all checks must pass on a fresh window, then start the 500ms delay
                    if(ms_tick&&speed_cnt==0&&sensor_ok&&position_safe&&config_ready
                       &&(down_cnt>=5)&&position_still&&angle_still) begin
                        settling<=1; settle_ms<=10'd500;
                    end
                end
            end else if(swing_enable&&capture_request) begin
                state<=BALANCE; capture_clear<=1;
            end
        end
    end
endmodule
