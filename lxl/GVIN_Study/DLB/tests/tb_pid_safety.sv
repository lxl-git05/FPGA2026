`timescale 1ns/1ps
module tb_pid_safety;
    reg clk=0,rst_n=0,ms=0,key=0,captured=0;
    reg [11:0] raw=2180,angle=2180;
    wire sensor,capture,safe,position_safe,fault,active,balancing,swing_enable,motor_enable,clear;
    wire [3:0] reason,latched;
    wire [2:0] state;
    wire signed [31:0] origin,motor,pwm;
    wire sample,av,bv;
    wire [11:0] sample_adc;
    integer samples=0,acount=0,bcount=0,before_a,before_b;
    always #10 clk=~clk;
    safety_guard #(.ADC_RANGE_ONLY(1)) guard(
        .clk(clk),.rst_n(rst_n),.ms_tick(ms),.active(active),.balancing(balancing),
        .raw_valid(1'b1),.raw_otr(1'b1),.angle_valid(1'b0),.raw_adc(raw),.angle_adc(angle),
        .balance_sample_valid(sample),.balance_angle_adc(sample_adc),
        .rail_low(12'd64),.rail_high(12'd4032),.capture_adc(12'd500),.fall_adc(12'd700),
        .center_adc(32'sd2180),.position_count(32'sd0),.travel_counts(32'd10400),.adc_timeout_ms(16'd3),
        .sensor_ok(sensor),.capture_allowed(capture),.balance_safe(safe),.position_safe(position_safe),
        .fault_now(fault),.fault_reason(reason));
    run_control run(.clk(clk),.rst_n(rst_n),.key_press(key),.sensor_ok(sensor),.position_safe(position_safe),
        .config_ready(1'b1),.auto_start(1'b0),.fault_now(fault),.fault_reason(reason),
        .capture_request(captured),.swing_timed_out(1'b0),.encoder_count(32'sd0),
        .pid_pwm_ticks(pwm),.swing_pwm_ticks(32'sd0),.state(state),.fault_code(latched),
        .position_origin(origin),.capture_clear(clear),.active(active),.balancing(balancing),
        .swing_enable(swing_enable),.motor_enable(motor_enable),.motor_pwm_ticks(motor));
    cascade_control controller(.clk(clk),.rst_n(rst_n),.ms_tick(ms),
        .enable(balancing&&!fault&&!key),.capture_clear(clear),.dual_loop(1'b1),
        .period_a_ms(16'd5),.period_b_ms(16'd50),.outer_limit_adc(16'd100),.outer_i_adc(16'd100),
        .inner_limit_percent(8'd100),.inner_i_percent(8'd100),
        .center_adc(32'sd2180),.goal_position(32'sd100),.position_count(32'sd0),.angle_adc(angle),
        .kp_a(32'sd65536),.ki_a(32'sd0),.kd_a(32'sd0),
        .kp_b(32'sd65536),.ki_b(32'sd0),.kd_b(32'sd0),.epoch_a(32'd0),.epoch_b(32'd0),
        .pid_pwm_ticks(pwm),.a_goal(),.a_real(),.a_set_ticks(),.b_goal(),.b_real(),.b_set_adc(),
        .a_done(av),.b_done(bv),.a_sample_valid(sample),.a_sample_adc(sample_adc));
    always @(posedge clk) begin
        if(sample) samples++;
        if(av) acount++;
        if(bv) bcount++;
    end
    task check(input bit condition,input string message);
        if(!condition) $fatal(1,"FAIL PID safety: %s",message);
    endtask
    task millisecond;
        @(negedge clk); ms=1; @(negedge clk); ms=0;
        repeat(60) @(negedge clk);
    endtask
    task start_balance;
        angle=2180;
        @(negedge clk); key=1; @(negedge clk); key=0;
        @(negedge clk); captured=1; @(negedge clk); captured=0;
        repeat(4) @(negedge clk);
        check(balancing,"manual capture enters balance");
    endtask
    initial begin
        repeat(4) @(negedge clk); rst_n=1;
        repeat(3) @(negedge clk); start_balance();
        raw=4092; repeat(5) millisecond();
        check(balancing&&samples==1&&acount==1,"raw outlier ignored, safe 5ms feedback used");
        angle=3204; repeat(3) @(negedge clk); angle=2180;
        check(balancing,"feedback change outside sample boundary ignored");
        repeat(4) millisecond(); before_a=acount;
        angle=1476; millisecond();
        check(state==4&&latched==4&&motor==0,"unsafe PID snapshot latches fall fault and stops motor");
        check(acount==before_a,"unsafe sample does not launch inner PID");
        angle=2180; repeat(3) millisecond(); check(state==4,"fault remains latched");
        start_balance(); before_a=acount; before_b=bcount;
        repeat(50) millisecond();
        check(acount==before_a+10&&bcount==before_b+1,"safe simultaneous 5/50ms deadlines preserved");
        angle=1480; repeat(5) millisecond(); check(balancing,"lower boundary accepted");
        angle=2880; repeat(5) millisecond(); check(balancing,"upper boundary accepted");
        angle=2180; repeat(39) millisecond(); before_a=acount; before_b=bcount;
        angle=2884; millisecond();
        check(state==4&&latched==4&&motor==0,"unsafe simultaneous deadline stops motor");
        check(acount==before_a&&bcount==before_b,"fault cancels both PID launches before computation");
        $display("PASS PID safety sampling, cancellation, boundaries and restart"); $finish;
    end
    initial begin #10000000; $fatal(1,"timeout"); end
endmodule
