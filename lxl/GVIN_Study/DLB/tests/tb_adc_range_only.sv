`timescale 1ns/1ps
module tb_adc_range_only;
    reg clk=0,rst_n=0,ms=0,active=0,balancing=0,raw_valid=0,sample=0;
    reg [11:0] raw=2180,angle=2180;
    reg signed [31:0] position=0;
    wire sensor,capture,safe,position_safe,fault;
    wire [3:0] reason;
    always #10 clk=~clk;
    safety_guard #(.ADC_RANGE_ONLY(1)) guard(
        .clk(clk),.rst_n(rst_n),.ms_tick(ms),.active(active),.balancing(balancing),
        .balance_sample_valid(sample),.balance_angle_adc(angle),
        .raw_valid(raw_valid),.raw_otr(1'b1),.angle_valid(1'b0),.raw_adc(raw),.angle_adc(angle),
        .rail_low(12'd64),.rail_high(12'd4032),.capture_adc(12'd500),.fall_adc(12'd700),
        .center_adc(32'sd2180),.position_count(position),.travel_counts(32'd10400),.adc_timeout_ms(16'd3),
        .sensor_ok(sensor),.capture_allowed(capture),.balance_safe(safe),.position_safe(position_safe),
        .fault_now(fault),.fault_reason(reason));
    task check(input bit condition,input string message);
        if(!condition) $fatal(1,"FAIL ADC range-only: %s",message);
    endtask
    initial begin
        repeat(3) @(negedge clk); rst_n=1;
        #1; check(!sensor,"wait for first sample");
        raw_valid=1; @(negedge clk); raw_valid=0; active=1; balancing=1;
        #1; check(sensor&&capture&&safe&&!fault,"ignore OTR and invalid window");
        ms=1; repeat(10) @(negedge clk); ms=0;
        #1; check(sensor&&!fault,"ignore stale sample age");
        sample=1; angle=1480; raw=0; #1; check(!fault,"lower boundary inclusive");
        angle=2880; #1; check(!fault,"upper boundary inclusive");
        angle=1479; #1; check(fault&&reason==4,"below lower boundary");
        angle=2881; #1; check(fault&&reason==4,"above upper boundary");
        sample=0; #1; check(!fault,"outlier between PID samples ignored");
        sample=1; balancing=0; raw=0; #1; check(!fault,"range guard only while balancing");
        balancing=1; raw=2180; angle=2681; #1;
        check(!capture&&!fault,"capture width retained independently of fall range");
        angle=2180; position=10401; #1;
        check(fault&&reason==3,"positive travel protection retained");
        position=-10401; #1; check(fault&&reason==3,"negative travel protection retained");
        position=0; #1; check(!fault,"in-range recovery before run-control latch");
        $display("PASS ADC range-only boundaries and bypass policy"); $finish;
    end
endmodule
