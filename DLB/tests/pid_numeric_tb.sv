`timescale 1ns/1ps
module pid_numeric_tb;
    reg clk=0;
    always #10 clk=~clk;
    reg rst_n=0, en=1, clear_pid=0, p_tick=0, a_tick=0;
    reg signed [31:0] goal=1, real_position=0;
    reg signed [31:0] kp=26214, ki=0, kd=0;
    wire signed [31:0] p_out, a_out;
    wire p_valid, a_valid;
    wire signed [31:0] a_goal=32'sd2060-p_out;
    PID_Core outer_pid (
        .clk(clk),.rst_n(rst_n),.pid_en(en),.pid_clear(clear_pid),.pid_tick(p_tick),
        .target(goal),.feedback(real_position),.kp_q(kp),.ki_q(ki),.kd_q(kd),
        .out_max(32'sd100),.out_min(-32'sd100),.i_limit(32'sd100),
        .pid_out(p_out),.error_out(),.p_out(),.i_out(),.d_out(),.pid_valid(p_valid)
    );
    PID_Core inner_pid (
        .clk(clk),.rst_n(rst_n),.pid_en(en),.pid_clear(clear_pid),.pid_tick(a_tick),
        .target(a_goal),.feedback(32'sd2060),.kp_q(32'sd65536),.ki_q(32'sd0),.kd_q(32'sd0),
        .out_max(32'sd100),.out_min(-32'sd100),.i_limit(32'sd100),
        .pid_out(a_out),.error_out(),.p_out(),.i_out(),.d_out(),.pid_valid(a_valid)
    );
    task automatic step(input integer which,input integer expected);
        begin
            @(negedge clk); if(which==0) p_tick=1; else a_tick=1;
            @(negedge clk); p_tick=0; a_tick=0;
            if(which==0 ? (!p_valid || p_out!==expected) : (!a_valid || a_out!==expected))
                $fatal(1,"Numerical case %0d: p=%d a=%d expected=%d",which,p_out,a_out,expected);
        end
    endtask
    initial begin
        repeat(3) @(negedge clk); rst_n=1;
        step(0,0); // Original core truncates +0.399994 to integer zero.
        if(a_goal!==2060) $fatal(1,"Integer cascade");
        step(1,0);
        goal=-1; step(0,-1); step(1,1); // Arithmetic right shift floors negative output.
        // Error is 33 bits: opposite INT32 extremes cannot wrap into the wrong sign.
        goal=32'sh7fffffff; real_position=32'sh80000000; kp=65536;
        step(0,100);
        goal=32'sh80000000; real_position=32'sh7fffffff;
        step(0,-100);
        // Original core keeps fractional I internally, and retains I when Ki becomes zero.
        goal=1; real_position=0; kp=0; ki=32768;
        step(0,0); step(0,1);
        ki=32'sh7fffffff; step(0,100);
        ki=0; step(0,100);
        // Caller owns clear/enable; clear must suppress a coincident tick.
        ki=65536; @(negedge clk); p_tick=1;
        @(negedge clk); p_tick=0; en=0;
        @(negedge clk); if(p_valid || p_out!==0 || outer_pid.i_term_q!==0) $fatal(1,"Disable");
        en=1; clear_pid=1; p_tick=1; @(negedge clk);
        if(p_valid || p_out!==0) $fatal(1,"Clear priority");
        clear_pid=0; p_tick=0; step(0,1);
        rst_n=0; @(negedge clk); if(p_out!==0 || a_out!==0) $fatal(1,"Reset");
        $display("PASS: two original PID instances, integer cascade, signed Q16.16 gains, full INT32 error span, fractional/clamped I, original Ki=0 retention, caller clear/disable/reset");
        $finish;
    end
    initial begin #100000; $fatal(1,"Numeric test timeout"); end
endmodule
