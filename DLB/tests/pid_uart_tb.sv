`timescale 1ns/1ps
module pid_uart_tb;
    reg clk = 0;
    always #10 clk = ~clk;
    reg rst_n = 0, uart_rx = 1;
    reg [1:0] ab = 0;
    reg [2:0] events = 0;
    reg signed [31:0] feedback_value = 0;
    wire uart_tx, ds, sh_cp, st_cp, tb_in1, tb_in2, tb_pwm;
    wire adc_sclk, adc_din, adc_cs;
    Test dut (.clk(clk), .rst_n(rst_n), .key_in(4'b1111), .encoder_a(ab[1]),
        .encoder_b(ab[0]), .uart_rx(uart_rx), .uart_tx(uart_tx), .ADC_DOUT(1'b0),
        .ADC_SCLK(adc_sclk), .ADC_DIN(adc_din), .ADC_CS_N(adc_cs),
        .ds(ds), .sh_cp(sh_cp), .st_cp(st_cp), .tb_in1(tb_in1), .tb_in2(tb_in2), .tb_pwm(tb_pwm));

    // Independent wide integer reference model, including fractional integration.
    reg signed [71:0] model_i = 0, model_last = 0, e, q, p, d, expected;
    reg pending = 0, check_period = 1;
    integer updates = 0, frames = 0, writes = 0, crc_errors = 0, type_errors = 0, id_errors = 0;
    time last_tick = 0;
    always @(posedge clk) begin
        if (!rst_n) begin
            model_i = 0; model_last = 0; pending = 0; last_tick = 0;
        end else begin
            if (dut.parameter_update) begin
                model_i = 0;
                e = $signed(dut.goal); e = e - $signed(dut.real_position);
                model_last = e; pending = 0;
            end else if (dut.pid_tick) begin
                if (check_period && last_tick != 0 && $time-last_tick != 20000000)
                    $fatal(1, "PID interval is not 20ms");
                last_tick = $time;
                if (pending) $fatal(1, "PID did not complete before next tick");
                e = $signed(dut.goal); e = e - $signed(dut.real_position);
                p = e * $signed(dut.kp);
                d = (e-model_last) * $signed(dut.kd);
                model_i = model_i + e * $signed(dut.ki);
                if (model_i > (72'sd500 <<< 16)) model_i = 72'sd500 <<< 16;
                if (model_i < (-72'sd500 <<< 16)) model_i = -72'sd500 <<< 16;
                q = p + model_i + d;
                if (q > (72'sd2500 <<< 16)) q = 72'sd2500 <<< 16;
                if (q < (-72'sd2500 <<< 16)) q = -72'sd2500 <<< 16;
                expected = q >>> 16; model_last = e; pending = 1;
            end
            if (dut.parameter_manager_inst.update_done) writes = writes+1;
            if (dut.protocol_rx_inst.crc_error) crc_errors = crc_errors+1;
            if (dut.parameter_manager_inst.type_error) type_errors = type_errors+1;
            if (dut.parameter_manager_inst.id_error) id_errors = id_errors+1;
            #1;
            if (dut.pid_valid) begin
                if (!pending || $signed(dut.pid_out) !== expected)
                    $fatal(1, "PID mismatch output=%d expected=%d pending=%d", dut.pid_out, expected, pending);
                if ($signed(dut.PWM) !== expected || $signed(dut.pid_error) !== e)
                    $fatal(1, "PID error/PWM mismatch");
                pending = 0; updates = updates+1;
            end
        end
    end

    function automatic [15:0] crc_step(input [15:0] crc, input [7:0] b);
        reg [15:0] c;
        begin
            c = crc ^ b;
            for (integer n = 0; n < 8; n=n+1) c = c[0] ? (c >> 1)^16'ha001 : c >> 1;
            crc_step = c;
        end
    endfunction
    reg [31:0] expected_fields [0:6];
    reg [223:0] frozen;
    reg expect_frame = 0;
    always @(posedge clk) begin
        if (rst_n && dut.send_en) begin
            if (dut.tx_busy || expect_frame) $fatal(1, "Duplicate frame request");
            expected_fields[0] = dut.frame_goal; expected_fields[1] = dut.frame_real;
            expected_fields[2] = dut.frame_error; expected_fields[3] = dut.frame_set;
            expected_fields[4] = dut.frame_kp; expected_fields[5] = dut.frame_ki; expected_fields[6] = dut.frame_kd;
            frozen = {dut.frame_goal,dut.frame_real,dut.frame_error,dut.frame_set,dut.frame_kp,dut.frame_ki,dut.frame_kd};
            expect_frame = 1;
        end
        if (rst_n && dut.tx_busy && frozen !== {dut.frame_goal,dut.frame_real,dut.frame_error,dut.frame_set,dut.frame_kp,dut.frame_ki,dut.frame_kd})
            $fatal(1, "Telemetry snapshot changed during transmission");
    end

    // Decode physical TX pin at 115200, without using the RTL UART receiver.
    reg [7:0] received [0:52];
    reg [7:0] b;
    reg [15:0] crc;
    reg [31:0] bits;
    integer cursor = 0, seq = 0, hex_file, command_file;
    initial begin
        hex_file = $fopen("telemetry.hex", "w");
        command_file = $fopen("commands.hex", "w");
        forever begin
            @(negedge uart_tx);
            if (rst_n) begin
                #4340;
                if (uart_tx !== 0) $fatal(1, "Bad start bit");
                for (integer bit_index=0; bit_index<8; bit_index=bit_index+1) begin
                    #8680; b[bit_index] = uart_tx;
                end
                #8680;
                if (uart_tx !== 1) $fatal(1, "Bad stop bit/baud rate");
                received[cursor] = b;
                cursor = cursor+1;
                if (cursor == 53) begin
                    if (!expect_frame) $fatal(1, "Unrequested telemetry");
                    if ({received[0],received[1],received[2],received[3]} !== 32'ha55a0101 ||
                        {received[7],received[6]} !== 16'd43 || received[8] !== 7)
                        $fatal(1, "Invalid telemetry header/length/count");
                    if ({received[5],received[4]} !== seq[15:0]) $fatal(1, "Bad SEQ");
                    crc = 16'hffff;
                    for (integer n=2; n<51; n=n+1) crc = crc_step(crc, received[n]);
                    if ({received[52],received[51]} !== crc) $fatal(1, "Bad telemetry CRC");
                    for (integer n=0; n<7; n=n+1) begin
                        if (received[9+6*n] !== (n<4 ? 8'(n+1) : 8'(n+12)) ||
                            received[10+6*n] !== (n<4 ? 8'h01 : 8'h03)) $fatal(1, "Bad channel ID/TYPE");
                        bits = {received[14+6*n],received[13+6*n],received[12+6*n],received[11+6*n]};
                        if (bits !== expected_fields[n]) $fatal(1, "Channel %d mismatch %h expected %h", n, bits, expected_fields[n]);
                    end
                    for (integer n=0; n<53; n=n+1) $fwrite(hex_file, "%02x ", received[n]);
                    $fwrite(hex_file, "\n");
                    seq = seq+1; frames = frames+1; cursor = 0; expect_frame = 0;
                end
            end
        end
    end

    task automatic uart_byte(input [7:0] value);
        begin
            uart_rx = 0; #8680;
            for (integer n=0; n<8; n=n+1) begin uart_rx = value[n]; #8680; end
            uart_rx = 1; #8680;
        end
    endtask
    task automatic write_param(input [7:0] id, input [7:0] kind, input [31:0] value, input bad_crc);
        reg [7:0] packet [0:15];
        reg [15:0] c;
        begin
            packet[0]=8'ha5; packet[1]=8'h5a; packet[2]=1; packet[3]=8'h10;
            packet[4]=8'h34; packet[5]=8'h12; packet[6]=6; packet[7]=0;
            packet[8]=id; packet[9]=kind;
            packet[10]=value[7:0]; packet[11]=value[15:8]; packet[12]=value[23:16]; packet[13]=value[31:24];
            c=16'hffff;
            for(integer n=2;n<14;n=n+1) c=crc_step(c,packet[n]);
            if (bad_crc) c=c^16'h0100;
            packet[14]=c[7:0]; packet[15]=c[15:8];
            for(integer n=0;n<16;n=n+1) $fwrite(command_file, "%02x ", packet[n]);
            $fwrite(command_file, "\n");
            @(negedge clk);
            for(integer n=0;n<16;n=n+1) uart_byte(packet[n]);
            repeat(15) @(negedge clk);
        end
    endtask
    task automatic pulse(input [2:0] mask);
        begin
            @(negedge clk); events=mask;
            @(negedge clk); events=0;
        end
    endtask
    task automatic update_now;
        integer before_updates;
        begin
            before_updates=updates;
            @(negedge clk); dut.control_counter=20'd999998;
            wait(updates>before_updates);
            repeat(5) @(negedge clk);
        end
    endtask
    task automatic drain;
        begin
            wait(!dut.tx_busy && !expect_frame && !dut.send_en);
            repeat(5) @(negedge clk);
        end
    endtask
    task automatic feedback(input integer value);
        begin @(negedge clk); feedback_value=value; update_now; end
    endtask

    initial begin
        force dut.key_release=events;
        repeat(5) @(negedge clk); rst_n=1;
        wait(updates==2); drain;
        if (dut.goal !== 0 || dut.PWM !== 0 || dut.kp !== 1623462 || dut.ki !== 0 || dut.kd !== 1341560)
            $fatal(1,"Reset defaults changed");
        if ({adc_cs,adc_sclk,adc_din} !== 3'b100) $fatal(1,"ADC not parked");
        check_period=0;
        pulse(1); update_now;
        if(dut.goal !== 102 || dut.PWM !== 2500 || {tb_in1,tb_in2} !== 2'b01) $fatal(1,"Positive target/saturation/direction");
        // Encoder integration through the physical AB inputs.
        ab=1; repeat(6) @(negedge clk); ab=3; repeat(6) @(negedge clk);
        ab=2; repeat(6) @(negedge clk); ab=0; repeat(6) @(negedge clk);
        if (dut.position_cnt !== 4) $fatal(1,"Encoder positive count");
        ab=2; repeat(6) @(negedge clk); ab=3; repeat(6) @(negedge clk);
        ab=1; repeat(6) @(negedge clk); ab=0; repeat(6) @(negedge clk);
        if (dut.position_cnt !== 0) $fatal(1,"Encoder reverse count");
        force dut.position_cnt=feedback_value;
        // Good CRC updates, bad CRC/type/ID rejected; all over actual RX pin.
        write_param(8'h10,3,32'd65536,0);
        if(dut.kp !== 65536 || dut.PWM !== 0) $fatal(1,"Kp write/clear");
        write_param(8'h11,3,32'd32768,0);
        write_param(8'h12,3,32'd16384,0);
        write_param(8'h10,3,32'd131072,1);
        write_param(8'h10,1,32'd131072,0);
        write_param(8'h55,3,32'd131072,0);
        if(dut.kp !== 65536 || dut.ki !== 32768 || dut.kd !== 16384 || writes !== 3 ||
           crc_errors !== 1 || type_errors !== 1 || id_errors !== 1) $fatal(1,"Write/rejection accounting");
        drain; feedback(100); drain; update_now;
        if(dut.PWM !== 4) $fatal(1,"Integral fractional accumulation");
        // Update during transmission must not change the locked coefficients in that frame.
        write_param(8'h11,3,32'd65536,0);
        drain; feedback(0);
        repeat(10) update_now;
        if(dut.PID_Core_inst.i_out !== 500) $fatal(1,"Positive integral clamp");
        drain;
        pulse(4); if(dut.position_cnt !== 0 || dut.goal !== 0) $fatal(1,"Home changed encoder");
        feedback(112); repeat(10) update_now;
        if(dut.PID_Core_inst.i_out !== -500 || $signed(dut.PWM)>=0 || {tb_in1,tb_in2} !== 2'b10)
            $fatal(1,"Negative integral/direction");
        drain;
        write_param(8'h10,3,32'd19660800,0); // Kp=300
        if(dut.PWM !== 0 || dut.PID_Core_inst.i_out !== 0) $fatal(1,"Parameter change did not clear integral");
        update_now; if(dut.PWM !== -2500) $fatal(1,"Negative output clamp");
        drain;
        // Signed Q16.16 and fractional values round-trip bit-exactly.
        write_param(8'h12,3,32'hffff8000,0); // Kd=-0.5
        drain; feedback(-12345); drain;
        repeat(80) @(negedge clk);
        if(dut.Data !== 32'd25002345 || dut.Seg8_inst.pending_digits !== 32'h25002345)
            $fatal(1,"Split display");
        pulse(3); if(dut.goal !== 0) $fatal(1,"Simultaneous +/- keys");
        pulse(2); if(dut.goal !== -102) $fatal(1,"Negative goal");
        pulse(5); if(dut.goal !== 0 || dut.position_cnt !== -12345) $fatal(1,"Home priority/origin");
        // Full signed encoder/target span needs a 33-bit error; telemetry saturates INT32.
        drain;
        @(negedge clk); dut.target_position=32'sh7fffffff;
        feedback(-2147483648); drain;
        if(dut.pid_error !== 33'sd4294967295 || dut.frame_error !== 32'sh7fffffff || dut.PWM !== 2500)
            $fatal(1,"Positive full-span error/clipping");
        @(negedge clk); dut.target_position=32'sh80000000;
        feedback(2147483647); drain;
        if(dut.pid_error !== -33'sd4294967295 || dut.frame_error !== 32'sh80000000 || dut.PWM !== -2500)
            $fatal(1,"Negative full-span error/clipping");
        write_param(8'h10,3,32'h80000000,0);
        write_param(8'h11,3,32'h7fffffff,0);
        write_param(8'h12,3,32'h80000000,0);
        update_now; drain; // The independent model also checks wide signed products.
        release dut.position_cnt;
        @(negedge clk); rst_n=0;
        repeat(5) @(negedge clk);
        if(dut.kp !== 1623462 || dut.ki !== 0 || dut.kd !== 1341560 || dut.PWM !== 0 || dut.position_cnt !== 0 || dut.goal !== 0)
            $fatal(1,"Reset restoration");
        if(frames<7) $fatal(1,"Insufficient telemetry coverage");
        $fclose(hex_file);
        $fclose(command_file);
        $display("PASS: %0d PID updates, %0d physical UART frames, %0d accepted writes; CRC/type/ID rejection, +/- clamps, snapshot, reset, keys, encoder, display", updates,frames,writes);
        $finish;
    end
    initial begin #200000000; $fatal(1,"PID UART test timeout"); end
endmodule
