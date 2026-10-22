`timescale 1ns/1ps
// Arithmetic equivalence and cancellation checks, independent of UART and mechanics.
module tb_pid_pipeline;
    reg clk=0;
    always #10 clk=~clk;
    reg rst_n=0, en=1, clear=0, tick=0;
    reg signed [31:0] target=0, feedback=0, kp=0, ki=0, kd=0;
    reg signed [31:0] hi=2500, lo=-2500, ilim=500;
    wire signed [31:0] out, po, io, do_;
    wire signed [32:0] eo;
    wire valid;
    PID_Core dut(.clk(clk),.rst_n(rst_n),.pid_en(en),.pid_clear(clear),.pid_tick(tick),
        .target(target),.feedback(feedback),.kp_q(kp),.ki_q(ki),.kd_q(kd),
        .out_max(hi),.out_min(lo),.i_limit(ilim),.pid_out(out),.error_out(eo),
        .p_out(po),.i_out(io),.d_out(do_),.pid_valid(valid));
    reg signed [127:0] hist=0, integral=0, e, pp, ii, dd, total, expected;
    reg signed [31:0] expected_p, expected_i, expected_d;
    integer checks=0;
    task check(input bit condition,input string msg);
        if(!condition) $fatal(1,"FAIL %s time=%t",msg,$time);
        checks++;
    endtask
    task calculate(input bit disturb_inputs);
        reg signed [31:0] previous;
        begin
            e=$signed(target); e=e-$signed(feedback);
            pp=e*$signed(kp); ii=integral+e*$signed(ki);
            if(ii>($signed(ilim)*128'sd65536)) ii=$signed(ilim)*128'sd65536;
            if(ii< -($signed(ilim)*128'sd65536)) ii=-($signed(ilim)*128'sd65536);
            dd=(e-hist)*$signed(kd); total=pp+ii+dd;
            if(total>$signed(hi)*128'sd65536) total=$signed(hi)*128'sd65536;
            if(total<$signed(lo)*128'sd65536) total=$signed(lo)*128'sd65536;
            expected=total>>>16;
            expected_p=pp>>>16; expected_i=ii>>>16; expected_d=dd>>>16;
            previous=out;
            @(negedge clk); tick=1;
            @(posedge clk); #1; check(!valid,"no immediate result");
            @(negedge clk); tick=0;
            if(disturb_inputs) begin
                target=1234567; feedback=-777; kp=123; ki=456; kd=-789;
                hi=17; lo=-19; ilim=3;
            end
            for(integer j=1;j<=8;j++) begin
                // A second trigger while busy must be ignored, including commit edge.
                tick=disturb_inputs;
                @(posedge clk); #1;
                if(j<8) check(!valid && out==previous,"output held during calculation");
                else begin
                    check(valid && $signed(out)==expected,"eight-clock result / integer equivalence");
                    check(eo==e && po==expected_p && io==expected_i && do_==expected_d,"debug snapshot");
                    integral=ii; hist=e;
                end
                @(negedge clk); tick=0;
            end
            @(posedge clk); #1; check(!valid,"one-clock valid pulse");
        end
    endtask
    task cancel(input integer kind,input integer delay_clocks);
        begin
            @(negedge clk); target=100; feedback=-50; tick=1;
            @(negedge clk); tick=0;
            repeat(delay_clocks) @(negedge clk);
            if(kind==0) clear=1;
            else if(kind==1) en=0;
            else rst_n=0;
            @(posedge clk); #1;
            check(!valid && out==0 && dut.i_term_q==0,"cancellation zeroes output/integral");
            integral=0; hist=(kind==2)?0:150;
            @(negedge clk); clear=0; en=1; rst_n=1;
            repeat(12) begin @(posedge clk); #1; check(!valid,"no stale completion after cancellation"); end
        end
    endtask
    initial begin
        repeat(3) @(negedge clk); rst_n=1;
        kp=555796; ki=0; kd=3402831; target=225;
        calculate(0);
        target=-225; calculate(0);
        kp=0; kd=0; ki=65536; target=1000; calculate(0);
        check(io==500,"positive integral clamp");
        target=-1000; calculate(0); check(io==-500,"negative integral clamp");
        for(integer j=0;j<100;j++) begin
            @(negedge clk);
            target=$random; feedback=$random; kp=$random; ki=$random; kd=$random;
            hi=2500; lo=-2500; ilim=500;
            calculate(j%2==0);
        end
        for(integer k=0;k<3;k++)
            for(integer stage=0;stage<8;stage++) cancel(k,stage);
        @(negedge clk); target=-1; feedback=0; kp=1; ki=0; kd=0;
        calculate(0); check(out==-1,"negative arithmetic shift floors");
        $display("PASS PID pipeline: %0d checks",checks); $finish;
    end
    initial begin #1000000; $fatal(1,"test timeout"); end
endmodule
