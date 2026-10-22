`timescale 1ns/1ps
// Self-checking integration test. Physical UART TX is decoded, not tx_data alone.
module tb_pid_motor;
    reg clk=0, rst_n=0, uart_rx=1;
    always #10 clk=~clk;
    wire uart_tx, in1, in2, pwm;
    top dut(.clk(clk),.rst_n(rst_n),.encoder_a(1'b0),.encoder_b(1'b0),
            .uart_rx(uart_rx),.uart_tx(uart_tx),.tb_in1(in1),.tb_in2(in2),.tb_pwm(pwm));
    localparam integer BIT_NS=8680;
    integer checks=0, frames=0, queued=0;
    string expected[128];
    string received="";
    reg [7:0] observed, injected;
    integer bitno;
    reg signed [31:0] simulated_position=0;
    reg signed [127:0] model_i=0, model_last=0, e, p, d, sum, want;
    integer cycles=0, last_boundary=0;
    integer pending_clocks=0, result_cycle=0;
    bit pending_result=0;

    task check(input bit condition, input string message);
        if (!condition) $fatal(1,"FAIL: %s at %t",message,$time);
        checks++;
    endtask
    task physical_byte(input reg [7:0] b);
        uart_rx=0; #(BIT_NS);
        for(integer j=0;j<8;j++) begin uart_rx=b[j]; #(BIT_NS); end
        uart_rx=1; #(BIT_NS);
    endtask
    task physical_command(input string s);
        for(integer j=0;j<s.len();j++) physical_byte(s[j]);
        repeat(400) @(negedge clk);
    endtask
    // Parser tests inject at the unchanged UART receiver's byte interface.
    task bytes(input string s);
        for(integer j=0;j<s.len();j++) begin
            @(negedge clk); injected=s[j];
            force dut.rx_data=injected; force dut.rx_done=1'b1;
            @(negedge clk); force dut.rx_done=1'b0;
            repeat(300) @(negedge clk);
        end
        release dut.rx_data; release dut.rx_done;
        repeat(400) @(negedge clk);
    endtask
    task next_result;
        @(posedge dut.pid_valid); #2;
    endtask
    function automatic string fixed6(input reg signed [63:0] n);
        reg [63:0] a;
        begin
            a=(n<0)?-n:n;
            fixed6=$sformatf("%s%0d.%06d",(n<0)?"-":"",a/1000000,a%1000000);
        end
    endfunction
    function automatic reg signed [63:0] degrees(input reg signed [31:0] n);
        reg signed [63:0] a;
        begin a=n; a=(a<0)?-a:a; a=(a*360000000+520)/1040; degrees=(n<0)?-a:a; end
    endfunction

    // Independent wide arithmetic model also verifies clear priority/history.
    always @(posedge clk) begin
        if (!rst_n) begin
            model_i=0; model_last=0; cycles=0; last_boundary=0;
            pending_result=0; pending_clocks=0; result_cycle=0;
        end
        else begin
            cycles++;
            if (dut.control_due) begin
                if(last_boundary!=0) check(cycles-last_boundary==1000000,"20ms period");
                last_boundary=cycles;
            end
            e=$signed(dut.sample_target); e=e-$signed(dut.sample_position);
            if(pending_result) pending_clocks--;
            if(dut.pid_clear) begin model_i=0; model_last=e; pending_result=0; end
            else if(dut.pid_tick) begin
                check(!pending_result,"control trigger never overlaps calculation");
                p=e*$signed(dut.sample_kp);
                model_i=model_i+e*$signed(dut.sample_ki);
                if(model_i>32768000) model_i=32768000;
                if(model_i< -32768000) model_i= -32768000;
                d=(e-model_last)*$signed(dut.sample_kd); model_last=e;
                sum=p+model_i+d;
                if(sum>163840000) sum=163840000;
                if(sum< -163840000) sum= -163840000;
                want=sum>>>16;
                pending_result=1; pending_clocks=8;
            end
            #1;
            if(pending_result && pending_clocks==0) begin
                check(dut.pid_valid && $signed(dut.pid_out)==want,"pipelined PID arithmetic/clamp/history");
                check($signed(dut.pid_inst.i_term_q)==model_i,"integral contribution");
                if(result_cycle!=0) check(cycles-result_cycle>=999999 && cycles-result_cycle<=1000001,
                                          "result every 20ms, gain clear may add one clock");
                result_cycle=cycles; pending_result=0;
                expected[queued]={fixed6(dut.sample_goal_micro),",",degrees_text(dut.sample_position),",",
                                  fixed6($signed(dut.pid_out)*64'sd40000),8'h0d,8'h0a};
                queued++;
            end else check(!dut.pid_valid,"no premature or duplicate PID result");
        end
    end
    function automatic string degrees_text(input reg signed [31:0] n);
        degrees_text=fixed6(degrees(n));
    endfunction

    // Decode actual 115200/8N1 waveform including stop bit and CR LF bytes.
    initial forever begin
        @(negedge uart_tx); #(BIT_NS/2);
        check(uart_tx==0,"UART start bit");
        for(bitno=0;bitno<8;bitno++) begin #(BIT_NS); observed[bitno]=uart_tx; end
        #(BIT_NS); check(uart_tx==1,"UART stop bit");
        received={received,observed};
        if(observed==8'h0a) begin
            check(frames<queued,"snapshot precedes send");
            if(received!=expected[frames]) $fatal(1,"frame got [%s] want [%s]",received,expected[frames]);
            check(1,"six decimals / signed snapshot / CRLF");
            frames++; received="";
        end
    end

    reg signed [31:0] oldgain;
    initial begin
        force dut.position_cnt=simulated_position;
        repeat(10) @(negedge clk); rst_n=1;
        check(dut.config_kp==555796 && dut.config_ki==0 && dut.config_kd==3402831,"default coefficients");
        check(dut.config_target==0,"boot zero target");
        physical_command("@goal_A=78$#\r\n");
        check(dut.config_target==225 && dut.config_goal_micro==78000000,"physical RX / 78deg quantization");
        bytes("@Kp=0.80$#@Ki=0.51$#@Kd=0.49$#\r\n");
        check(dut.config_kp==453711 && dut.config_ki==5785 && dut.config_kd==13894892,"C gain conversion");
        oldgain=dut.config_kp;
        bytes("@kp=2$#@Kp=1.1234567$#@Kp=1e3$#@Kp=999999999999999999999$#");
        check(dut.config_kp==oldgain,"case / precision / exponent / overflow rejection");
        bytes("@Kp=4000$#@Kp=18446744073709.551615$#");
        check(dut.config_kp==oldgain,"gain and normalization overflow rejection");
        bytes("@goal_A=-78.000000$#");
        check(dut.config_target== -225 && dut.config_goal_micro== -78000000,"negative goal");
        bytes("@goal_A=12");
        repeat(10) @(negedge clk);
        check(dut.config_target== -225,"incomplete frame no commit");
        bytes(".5$#"); check(dut.config_goal_micro==12500000,"split command");
        bytes("@goal_A=1@goal_A=78$#"); check(dut.config_target==225,"new @ resynchronizes");
        bytes("@goal_A=0000000000000000000000000000000000000001$#");
        check(dut.config_target==225,"overlength rejection");
        bytes("@goal_A=99");
        @(negedge clk); force dut.rx_age=23'd4999999;
        @(negedge clk); release dut.rx_age;
        bytes("$#"); check(dut.config_target==225,"100ms timeout threshold rejects remainder");
        simulated_position=225;
        wait(frames>=2);
        simulated_position= -225;
        bytes("@Kp=0$#@Kd=0$#@Ki=1000$#");
        next_result();
        next_result();
        check(dut.pid_inst.i_out==500,"positive integral limit");
        bytes("@goal_A=-360$#");
        next_result();
        check(dut.pid_inst.i_out== -500,"negative integral limit / target retains history");
        bytes("@Ki=0$#");
        wait(dut.pid_clear); @(negedge clk); @(negedge clk);
        check(dut.pid_inst.i_term_q==0,"gain clears integral");
        wait(frames==queued && frames>=5);
        $display("PASS PID_Motor: %0d checks, %0d physical UART frames",checks,frames);
        $finish;
    end
    initial begin #300000000; $fatal(1,"test timeout"); end
endmodule
