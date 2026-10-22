`timescale 1ns/1ps
module tb_safety;
    reg clk=0,rst_n=0,ms=0,key=0;
    always #10 clk=~clk;
    reg [9:0] code=0; reg otr=1;
    wire adc_clk,oe,raw_valid,raw_otr,window_valid,valid;
    wire [11:0] raw,angle;
    wire sensor,capture,safe,position_safe,fault;
    wire [3:0] reason,latched;
    wire active,balancing,swing_enable,motor_enable,capture_clear;
    wire [2:0] state;
    wire signed [31:0] origin,motor;
    reg captured=0; reg signed [31:0] position=0;
    adc_frontend #(.SAMPLE_TICKS(8)) ad(.clk(clk),.rst_n(rst_n),.adc_data_in(code),.adc_otr(otr),
        .rail_low(12'd64),.rail_high(12'd4032),.adc_clk(adc_clk),.adc_oe_n(oe),
        .raw_adc(raw),.angle_adc(angle),.raw_valid(raw_valid),.raw_otr(raw_otr),.window_valid(window_valid),.angle_valid(valid));
    safety_guard guard(.clk(clk),.rst_n(rst_n),.ms_tick(ms),.active(active),.balancing(balancing),
        .raw_valid(raw_valid),.raw_otr(raw_otr),.angle_valid(valid),.raw_adc(raw),.angle_adc(angle),
        .balance_sample_valid(window_valid),.balance_angle_adc(angle),
        .rail_low(12'd64),.rail_high(12'd4032),.capture_adc(12'd500),.fall_adc(12'd700),
        .center_adc(32'sd2180),.position_count(position),.travel_counts(32'd10400),.adc_timeout_ms(16'd3),
        .sensor_ok(sensor),.capture_allowed(capture),.balance_safe(safe),.position_safe(position_safe),
        .fault_now(fault),.fault_reason(reason));
    run_control run(.clk(clk),.rst_n(rst_n),.key_press(key),.sensor_ok(sensor),.position_safe(position_safe),
        .config_ready(1'b1),.auto_start(1'b1),.fault_now(fault),.capture_request(captured),
        .swing_timed_out(1'b0),.fault_reason(reason),.encoder_count(position),
        .pid_pwm_ticks(32'sd1250),.swing_pwm_ticks(32'sd875),.state(state),.fault_code(latched),
        .position_origin(origin),.capture_clear(capture_clear),.active(active),.balancing(balancing),
        .swing_enable(swing_enable),.motor_enable(motor_enable),.motor_pwm_ticks(motor));
    integer checks=0;
    task check(input bit condition,input string msg);
        if(!condition) $fatal(1,"FAIL safety: %s",msg); checks++;
    endtask
    task press;
        @(negedge clk); key=1; @(negedge clk); key=0; @(negedge clk);
    endtask
    task fresh_window;
        repeat(260) @(negedge clk);
    endtask
    initial begin
        repeat(4) @(negedge clk); rst_n=1;
        fresh_window(); check(!valid && angle==0 && sensor,"zero/OTR blind zone allows arming");
        check(state==0 && motor==0,"power on stopped");
        press(); check(state==2 && motor==875,"auto swing starts at zero with OTR high");
        // A window straddles full-scale and zero. Never expose their false midpoint as valid.
        code=0; repeat(20) @(negedge clk); code=1023;
        fresh_window(); check(!valid && !capture,"rail window cannot capture");
        check(sensor && state==2 && motor==875,"full-scale/OTR blind zone is not stale stream");
        code=545; otr=0; fresh_window(); check(capture && angle==2180,"recovered valid mean and capture permission");
        @(negedge clk); captured=1; @(negedge clk); captured=0;
        @(negedge clk); check(balancing && motor==1250,"balance entry");
        code=721; fresh_window();
        check(state==4 && motor==0 && latched==4,"sampled feedback error >700 kills PWM");
        code=545; fresh_window(); check(state==4 && motor==0,"no automatic restart");
        press(); check(state==2,"explicit fault restart");
        @(negedge clk); captured=1; @(negedge clk); captured=0;
        @(negedge clk); check(balancing,"second balance entry");
        code=0; otr=1; repeat(20) @(negedge clk);
        check(state==4 && motor==0 && latched==2,"balancing NEVER exempts rail OTR");
        code=545; otr=0; fresh_window(); press();
        position=10401; @(negedge clk); @(negedge clk);
        check(state==4 && motor==0 && latched==3,"travel guard independent of goal");
        position=0; press(); otr=1; repeat(20) @(negedge clk);
        check(state==4 && motor==0 && latched==2,"ADC OTR stop");
        otr=0; fresh_window(); press();
        force raw_valid=1'b0;
        repeat(3) begin @(negedge clk); ms=1; @(negedge clk); ms=0; end
        repeat(3) @(negedge clk);
        check(state==4 && motor==0 && latched==1,"stale ADC stop");
        release raw_valid;
        $display("PASS sensor/safety/run: %0d checks",checks); $finish;
    end
    initial begin #1000000; $fatal(1,"timeout"); end
endmodule
