`timescale 1ns/1ps
module tb_protocol;
    reg clk=0,rst_n=0;
    always #10 clk=~clk;
    reg [7:0] data=0; reg rx_done=0;
    wire parsed; wire [7:0] id; wire signed [63:0] micro;
    reg direct=0,request=0,stopped=1;
    reg [7:0] direct_id; reg signed [63:0] direct_micro;
    wire ready; wire signed [31:0] center,goal,ka,ia,da,kb,ib,db;
    wire [31:0] ea,eb; wire [15:0] period_a;
    integer checks=0;
    command_rx parser(.clk(clk),.rst_n(rst_n),.rx_data(data),.rx_done(rx_done),
        .write_valid(parsed),.write_id(id),.write_micro(micro));
    config_bank cfg(.clk(clk),.rst_n(rst_n),.stopped(stopped),.ready(ready),
        .write_valid(direct?request:parsed),.write_id(direct?direct_id:id),
        .write_micro(direct?direct_micro:micro),.center_adc(center),.goal_position(goal),
        .kp_a(ka),.ki_a(ia),.kd_a(da),.kp_b(kb),.ki_b(ib),.kd_b(db),
        .epoch_a(ea),.epoch_b(eb),.period_a_ms(period_a));
    task check(input bit condition,input string msg);
        if(!condition) $fatal(1,"FAIL protocol: %s",msg); checks++;
    endtask
    task bytes(input string text);
        for(integer i=0;i<text.len();i++) begin
            @(negedge clk); data=text[i]; rx_done=1;
            @(negedge clk); rx_done=0;
            repeat(300) @(negedge clk);
        end
        repeat(300) @(negedge clk);
    endtask
    task config_write(input reg [7:0] n,input reg signed [63:0] v);
        wait(ready); @(negedge clk); direct=1; direct_id=n; direct_micro=v; request=1;
        @(negedge clk); request=0;
        repeat(1500) @(negedge clk); direct=0;
        check(ready,"conversion completed");
    endtask
    reg signed [31:0] old;
    initial begin
        repeat(4) @(negedge clk); rst_n=1; @(negedge clk);
        check(center==2180 && goal==0,"measured upright default");
        check(ka==622592 && ia==0 && da==3932160,"A default continuous gains");
        check(kb==0 && ib==0 && db==0,"B default scale after six-decimal normalization");
        bytes("@Kp_A=0.80$#@Ki_A=0.51$#@Kd_A=0.49$#\r\n");
        check(ka==1310720 && ia==4178 && da==160563200,"A gain conversion");
        bytes("@Kp_B=0.80$#@Ki_B=0.51$#@Kd_B=0.49$#");
        check(kb==52429 && ib==1671 && db==642253,"B gain conversion");
        bytes("@goal_B=-1040$#@goal_A=2180$#");
        check(goal==-1040 && center==2180,"signed count target");
        bytes("@goal_A=10$#@goal_A=4000$#@goal_B=10401$#");
        check(goal==-1040 && center==2180,"range rejection");
        old=ka;
        bytes("@kp_A=2$#@Kp_A=1.1234567$#@Kp_A=1e3$#@Kp_A=999999999999999999999$#");
        bytes("@Kp_A=00000000000000000000000000000000001$#");
        check(ka==old,"bad name, precision, exponent, overflow, length");
        bytes("@goal_B=1"); check(goal==-1040,"split not submitted");
        bytes(".5$#"); check(goal==2,"symmetric rounding");
        bytes("@goal_B=-1.5$#"); check(goal==-2,"negative half rounding");
        bytes("@goal_B=123");
        @(negedge clk); force parser.rx_age=23'd4999999;
        @(negedge clk); release parser.rx_age;
        bytes("$#"); check(goal==-2,"timeout discards partial");
        bytes("@goal_B=0@goal_B=1040$#"); check(goal==1040,"new @ restarts frame");
        bytes("@Kp_A=-0.5$#"); check(ka==-819200,"negative gain");
        config_write(8'h82,64'sd10000000);
        check(period_a==10 && ia==8356 && da==80281600,"period transaction recomputes I/D");
        stopped=0; config_write(8'h82,64'sd20000000);
        check(period_a==10,"global write forbidden while running");
        stopped=1; config_write(8'h82,-64'sd1000000);
        check(period_a==10,"negative global forbidden");
        $display("PASS protocol/config: %0d checks",checks); $finish;
    end
    initial begin #30000000; $fatal(1,"timeout"); end
endmodule
