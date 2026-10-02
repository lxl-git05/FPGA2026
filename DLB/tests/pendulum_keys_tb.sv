`timescale 1ns/1ps
module pendulum_keys_tb;
    reg clk = 0;
    always #10 clk = ~clk;
    reg rst_n = 0;
    reg [3:0] key_in = 4'b1111;
    reg [1:0] ab = 0;
    reg adc_dout = 0;
    wire adc_sclk, adc_cs;
    Test dut (
        .clk(clk), .rst_n(rst_n), .key_in(key_in), .encoder_a(ab[1]), .encoder_b(ab[0]),
        .uart_rx(1'b1), .uart_tx(), .ADC_DOUT(adc_dout), .ADC_SCLK(adc_sclk),
        .ADC_DIN(), .ADC_CS_N(adc_cs), .tb_in1(), .tb_in2(), .tb_pwm(),
        .ds(), .sh_cp(), .st_cp()
    );
    reg [15:0] adc_word = {4'b0,12'd3000};
    integer adc_bit = 0;
    always @(negedge adc_cs) adc_bit = 0;
    always @(negedge adc_sclk) if (!adc_cs) adc_dout = adc_word[15-adc_bit];
    always @(posedge adc_sclk) if (!adc_cs && adc_bit < 15) adc_bit = adc_bit + 1;
    task automatic wait_ms(input integer count);
        begin repeat(count) begin @(posedge dut.ms_tick); @(posedge clk); @(negedge clk); end repeat(5) @(negedge clk); end
    endtask
    initial begin
        repeat(5) @(negedge clk); rst_n = 1; wait_ms(3);
        // Exercise real input synchronizers and debounce, without forcing key events.
        key_in[0]=0; wait_ms(5); key_in[0]=1; wait_ms(30);
        if(dut.target_position!==0) $fatal(1,"Short key glitch changed goal");
        key_in[0]=0; wait_ms(30);
        if(dut.target_position!==34) $fatal(1,"K1 must add34 on press");
        wait_ms(30); if(dut.target_position!==34) $fatal(1,"K1 repeated while held");
        key_in[0]=1; wait_ms(30);
        if(dut.target_position!==34) $fatal(1,"K1 release changed goal");
        key_in[1]=0; wait_ms(30);
        if(dut.target_position!==0) $fatal(1,"K2 must subtract34 on press");
        key_in[1]=1; wait_ms(30);
        if(dut.target_position!==0) $fatal(1,"K2 release changed goal");
        // A nonzero encoder count/goal must be preserved when starting and stopping.
        ab=1; repeat(6) @(negedge clk); ab=3; repeat(6) @(negedge clk); ab=2; repeat(6) @(negedge clk); ab=0; repeat(6) @(negedge clk);
        key_in[0]=0; wait_ms(30); key_in[0]=1; wait_ms(30);
        key_in[2]=0; wait_ms(30);
        if(dut.run_state!==22 || dut.PWM!==875 || dut.position_offset!==4 || dut.target_position!==34) $fatal(1,"K3 press/start origin/goal");
        ab=1; repeat(6) @(negedge clk); ab=3; repeat(6) @(negedge clk); ab=2; repeat(6) @(negedge clk); ab=0; repeat(6) @(negedge clk);
        key_in[2]=1; wait_ms(30);
        if(dut.run_state!==22) $fatal(1,"K3 release stopped swing");
        key_in[2]=0; wait_ms(30);
        if(dut.run_state!==0 || dut.PWM!==0 || dut.position_offset!==4 || dut.target_position!==34) $fatal(1,"Second K3 press changed origin/goal or did not stop");
        key_in[2]=1; wait_ms(30); key_in[2]=0; wait_ms(30);
        if(dut.run_state!==22 || dut.PWM!==875 || dut.position_offset!==8 || dut.target_position!==34) $fatal(1,"K3 restart origin/goal");
        // Freshness loss during a driven swing must stop the motor/state.
        force dut.adc_valid=0; wait_ms(4);
        if(dut.sensor_ok || dut.run_state!==0 || dut.PWM!==0 || dut.tb_pwm!==0)
            $fatal(1,"ADC timeout did not stop a running swing");
        release dut.adc_valid;
        @(negedge clk); rst_n=0; repeat(5) @(negedge clk);
        if(dut.target_position!==0 || dut.run_state!==0 || dut.PWM!==0) $fatal(1,"Reset");
        $display("PASS: physical key inputs; press +/-34, debounce, hold/release, K3 start/stop/restart, live ADC timeout, reset");
        $finish;
    end
    initial begin #500000000; $fatal(1,"Physical key test timeout"); end
endmodule
