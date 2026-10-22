`timescale 1ns/1ps
module tb_swing;
    reg clk=0,rst_n=0,ms=0,enable=0,auto_mode=1,valid=1,can_capture=0;
    always #10 clk=~clk;
    reg [11:0] angle=3000;
    reg [15:0] timeout_ms=10000;
    wire signed [31:0] pwm;
    wire capture,timeout;
    integer checks=0,captures=0;
    swing_up swing(.clk(clk),.rst_n(rst_n),.ms_tick(ms),.enable(enable),.auto_mode(auto_mode),
        .angle_valid(valid),.capture_allowed(can_capture),.angle_adc(angle),.capture_adc(12'd500),
        .center_adc(32'sd2180),.kick_percent(8'd35),.kick_ms(16'd100),.judge_ms(16'd40),
        .swing_timeout_ms(timeout_ms),.swing_pwm_ticks(pwm),.capture_request(capture),.timed_out(timeout));
    always @(posedge clk) if(capture) captures++;
    task check(input bit condition,input string msg);
        if(!condition) $fatal(1,"FAIL swing: %s",msg); checks++;
    endtask
    task tick;
        @(negedge clk); ms=1; @(negedge clk); ms=0;
    endtask
    initial begin
        repeat(4) @(negedge clk); rst_n=1; enable=1;
        repeat(2) @(negedge clk);
        check(pwm==875,"initial positive pulse");
        repeat(99) tick(); check(pwm==875,"positive lasts 100ms");
        tick(); check(pwm==-875,"then negative pulse");
        valid=0;
        repeat(99) tick(); check(pwm==-875,"blind zone does not pause pulse timer");
        tick(); check(pwm==0 && captures==0,"blind zone cannot capture");
        valid=1; angle=3000; repeat(40) tick();
        angle=2900; repeat(40) tick();
        angle=3000; repeat(40) tick();
        check(pwm==875,"three-point peak triggers next pulse");
        enable=0; repeat(3) @(negedge clk);
        auto_mode=0; enable=1; angle=2180; can_capture=1;
        repeat(3) @(negedge clk);
        repeat(40) tick(); check(captures==0 && pwm==0,"manual needs two capture judgments");
        repeat(40) tick(); repeat(3) @(negedge clk);
        check(captures==1 && pwm==0,"manual capture without motor kick");
        enable=0; repeat(3) @(negedge clk); captures=0;
        auto_mode=1; timeout_ms=50; can_capture=0; enable=1;
        repeat(3) @(negedge clk); repeat(50) tick();
        check(timeout,"total auto timeout");
        $display("PASS swing: %0d checks",checks); $finish;
    end
    initial begin #1000000; $fatal(1,"timeout"); end
endmodule
