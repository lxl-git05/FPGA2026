`timescale 1ns/1ps
module tb_cascade;
    reg clk=0,rst_n=0,ms=0,enable=0,clear=0,dual=1;
    always #10 clk=~clk;
    reg signed [31:0] center=2180,position=0,goal=100;
    reg [31:0] epoch=0;
    wire signed [31:0] pwm,ag,ar,aset,bg,br,bset;
    wire av,bv;
    wire signed [31:0] reversed_pwm,reversed_set,reversed_goal,reversed_bset;
    integer checks=0,acount=0,bcount=0,clk_sequence=0,last_b_sequence=0;
    cascade_control controller(.clk(clk),.rst_n(rst_n),.ms_tick(ms),.enable(enable),.capture_clear(clear),
        .dual_loop(dual),.period_a_ms(16'd5),.period_b_ms(16'd50),
        .outer_limit_adc(16'd100),.outer_i_adc(16'd100),.inner_limit_percent(8'd100),.inner_i_percent(8'd100),
        .center_adc(center),.goal_position(goal),.position_count(position),.angle_adc(12'd2180),
        .kp_a(32'sd65536),.ki_a(32'sd0),.kd_a(32'sd0),
        .kp_b(32'sd65536),.ki_b(32'sd0),.kd_b(32'sd0),.epoch_a(epoch),.epoch_b(epoch),
        .pid_pwm_ticks(pwm),.a_goal(ag),.a_real(ar),.a_set_ticks(aset),.b_goal(bg),.b_real(br),.b_set_adc(bset),
        .a_done(av),.b_done(bv));
    cascade_control #(.ANGLE_OUTPUT_SIGN(-1)) reversed_controller(
        .clk(clk),.rst_n(rst_n),.ms_tick(ms),.enable(enable),.capture_clear(clear),
        .dual_loop(dual),.period_a_ms(16'd5),.period_b_ms(16'd50),
        .outer_limit_adc(16'd100),.outer_i_adc(16'd100),.inner_limit_percent(8'd100),.inner_i_percent(8'd100),
        .center_adc(center),.goal_position(goal),.position_count(position),.angle_adc(12'd2180),
        .kp_a(32'sd65536),.ki_a(32'sd0),.kd_a(32'sd0),
        .kp_b(32'sd65536),.ki_b(32'sd0),.kd_b(32'sd0),.epoch_a(epoch),.epoch_b(epoch),
        .pid_pwm_ticks(reversed_pwm),.a_goal(reversed_goal),.a_real(),.a_set_ticks(reversed_set),
        .b_goal(),.b_real(),.b_set_adc(reversed_bset),.a_done(),.b_done());
    task check(input bit condition,input string msg);
        if(!condition) $fatal(1,"FAIL cascade: %s",msg); checks++;
    endtask
    task millisecond;
        @(negedge clk); ms=1; @(negedge clk); ms=0;
        repeat(45) @(negedge clk);
    endtask
    always @(posedge clk) begin
        clk_sequence++;
        if(av) begin acount++; if(acount==10) check(last_b_sequence<clk_sequence && last_b_sequence!=0,"B before A"); end
        if(bv) begin bcount++; last_b_sequence=clk_sequence; end
    end
    initial begin
        repeat(4) @(negedge clk); rst_n=1; enable=1; clear=1;
        @(negedge clk); clear=0;
        repeat(50) millisecond();
        check(acount==10 && bcount==1,"5/50ms rates");
        check(bset==100 && ag==2080 && aset==-100,"same-deadline A uses new B output");
        check(reversed_pwm==100 && reversed_set==100,"inner polarity reverses motor and reported PWM together");
        check(reversed_goal==ag && reversed_bset==bset,"inner polarity leaves cascade goal and encoder convention unchanged");
        check(br==0 && bg==100 && ar==2180,"complete loop snapshots");
        epoch=1; repeat(5) millisecond(); check(acount==11,"gain change clears then still computes");
        @(negedge clk); enable=0; @(negedge clk);
        check(pwm==0 && aset==0,"disable kills output");
        check(reversed_pwm==0 && reversed_set==0,"reversed polarity also disables cleanly");
        dual=0; enable=1; repeat(5) millisecond();
        check(bset==0 && ag==2180,"single loop uses upright directly");
        // Stop while the PID core is busy; no old result may re-enable output.
        repeat(4) millisecond();
        @(negedge clk); ms=1; @(negedge clk); ms=0;
        repeat(4) @(negedge clk); enable=0;
        repeat(20) @(negedge clk); check(pwm==0 && !av,"cancel in-flight result");
        $display("PASS cascade: %0d checks",checks); $finish;
    end
    initial begin #1000000; $fatal(1,"timeout"); end
endmodule
