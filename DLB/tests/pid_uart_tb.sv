`timescale 1ns/1ps
module pid_uart_tb;
    reg clk = 0;
    always #10 clk = ~clk;
    reg rst_n = 0, uart_rx = 1;
    reg [2:0] events = 0;
    reg [1:0] ab = 0;
    reg [11:0] sensor_angle = 3000;
    reg adc_dout = 0;
    wire uart_tx, ds, sh_cp, st_cp, tb_in1, tb_in2, tb_pwm, adc_sclk, adc_din, adc_cs;
    Test dut (.clk(clk), .rst_n(rst_n), .key_in(4'b1111), .encoder_a(ab[1]),
        .encoder_b(ab[0]), .uart_rx(uart_rx), .uart_tx(uart_tx), .ADC_DOUT(adc_dout),
        .ADC_SCLK(adc_sclk), .ADC_DIN(adc_din), .ADC_CS_N(adc_cs),
        .ds(ds), .sh_cp(sh_cp), .st_cp(st_cp), .tb_in1(tb_in1), .tb_in2(tb_in2), .tb_pwm(tb_pwm));

    // Behavioral ADC peripheral: command on rising SCLK, 4 null bits + 12 ADC bits.
    reg [15:0] adc_word, command;
    integer adc_bit = 0, adc_frames = 0;
    always @(negedge adc_cs) begin adc_word = {4'b0,sensor_angle}; adc_bit = 0; command = 0; end
    always @(negedge adc_sclk) if (!adc_cs) begin
        adc_dout = adc_word[15-adc_bit];
    end
    always @(posedge adc_sclk) if (!adc_cs) begin
        command = {command[14:0],adc_din};
        if (adc_bit < 15) adc_bit = adc_bit + 1;
    end
    always @(posedge adc_cs) if (rst_n) begin
        if (command[13:11] !== 0) $fatal(1,"ADC selected wrong channel");
        adc_frames = adc_frames + 1;
    end

    // Independent model of the unchanged PID_Core: integer ports, Q16.16 gains/I.
    wire [1:0] enabled = {dut.balance_en,dut.balance_en};
    wire [1:0] clear_pid = {dut.position_capture_clear || dut.p_update,dut.capture_clear || dut.a_update};
    wire [1:0] ticks = {dut.position_tick,dut.angle_tick};
    wire signed [31:0] target [0:1];
    wire signed [31:0] feedback [0:1];
    wire signed [31:0] kp [0:1], ki [0:1], kd [0:1], out_value [0:1];
    assign target[0]=dut.angle_goal_sample; assign target[1]=dut.position_goal_sample;
    assign feedback[0]=dut.a_feedback; assign feedback[1]=dut.position_sample;
    assign kp[0]=dut.a_kp; assign kp[1]=dut.p_kp;
    assign ki[0]=dut.a_ki; assign ki[1]=dut.p_ki;
    assign kd[0]=dut.a_kd; assign kd[1]=dut.p_kd;
    assign out_value[0]=dut.a_out; assign out_value[1]=dut.p_out;
    reg signed [71:0] model_i [0:1], model_last [0:1], expected [0:1];
    reg signed [71:0] e, p, d, q;
    integer updates [0:1];
    time last_tick [0:1];
    reg check_period = 1;
    reg [1:0] expected_valid;
    always @(posedge clk) begin
        expected_valid=0;
        for(integer n=0;n<2;n=n+1) begin
            e=$signed(target[n]); e=e-$signed(feedback[n]);
            if(!rst_n) begin model_i[n]=0; model_last[n]=0; expected[n]=0; last_tick[n]=0; expected_valid[n]=0; end
            else if(clear_pid[n] || !enabled[n]) begin model_i[n]=0; model_last[n]=e; expected[n]=0; last_tick[n]=0; expected_valid[n]=0; end
            else begin
              if(ticks[n]) begin
                if(check_period && last_tick[n]!=0 && $time-last_tick[n]!=(n==0 ? 5000000 : 50000000))
                    $fatal(1,"Wrong loop %0d period",n);
                last_tick[n]=$time;
                p=e*$signed(kp[n]); d=(e-model_last[n])*$signed(kd[n]); q=e*$signed(ki[n]);
                model_i[n]=model_i[n]+q;
                if(model_i[n]>(72'sd100<<<16)) model_i[n]=72'sd100<<<16;
                if(model_i[n]<(-72'sd100<<<16)) model_i[n]=-72'sd100<<<16;
                q=p+model_i[n]+d;
                if(q>(72'sd100<<<16)) q=72'sd100<<<16;
                if(q<(-72'sd100<<<16)) q=-72'sd100<<<16;
                expected[n]=q>>>16; model_last[n]=e; expected_valid[n]=1; updates[n]=updates[n]+1;
              end
            end
        end
        #1;
        if(rst_n && {dut.p_valid,dut.a_valid} !== expected_valid) $fatal(1,"PID valid mismatch");
        for(integer n=0;n<2;n=n+1)
            if(out_value[n] !== expected[n][31:0]) $fatal(1,"PID %0d output %d expected %d",n,out_value[n],expected[n]);
        if(!rst_n || !dut.motor_en) begin
            if({tb_in1,tb_in2,tb_pwm} !== 0) $fatal(1,"Disabled motor pins nonzero");
        end
        if($signed(dut.PWM)>2500 || $signed(dut.PWM)<-2500) $fatal(1,"PWM range");
    end

    function automatic [15:0] crc_step(input [15:0] old_crc,input [7:0] value);
        reg [15:0] c;
        begin c=old_crc^value; for(integer n=0;n<8;n=n+1) c=c[0] ? (c>>1)^16'ha001 : c>>1; crc_step=c; end
    endfunction
    reg [383:0] frozen;
    reg [31:0] expected_fields [0:11];
    reg expect_frame = 0;
    integer frames = 0, seq = 0, hex_file, command_file;
    always @(posedge clk) begin
        if(rst_n && dut.send_en) begin
            if(expect_frame) $fatal(1,"Frame overrun");
            expect_frame=1;
            frozen={dut.frame_a_goal,dut.frame_a_real,dut.frame_a_set,dut.frame_p_goal,dut.frame_p_real,dut.frame_p_set,
                    dut.frame_a_kp,dut.frame_a_ki,dut.frame_a_kd,dut.frame_p_kp,dut.frame_p_ki,dut.frame_p_kd};
            expected_fields[0]=dut.frame_a_goal; expected_fields[1]=dut.frame_a_real; expected_fields[2]=dut.frame_a_set;
            expected_fields[3]=dut.frame_p_goal; expected_fields[4]=dut.frame_p_real; expected_fields[5]=dut.frame_p_set;
            expected_fields[6]=dut.frame_a_kp; expected_fields[7]=dut.frame_a_ki; expected_fields[8]=dut.frame_a_kd;
            expected_fields[9]=dut.frame_p_kp; expected_fields[10]=dut.frame_p_ki; expected_fields[11]=dut.frame_p_kd;
        end
        if(rst_n && dut.tx_busy && frozen !== {dut.frame_a_goal,dut.frame_a_real,dut.frame_a_set,dut.frame_p_goal,dut.frame_p_real,dut.frame_p_set,
                                              dut.frame_a_kp,dut.frame_a_ki,dut.frame_a_kd,dut.frame_p_kp,dut.frame_p_ki,dut.frame_p_kd})
            $fatal(1,"Telemetry changed in flight");
    end
    reg [7:0] received [0:82], b;
    reg [15:0] crc;
    reg [31:0] bits;
    integer cursor = 0;
    initial begin
        hex_file=$fopen("telemetry.hex","w"); command_file=$fopen("commands.hex","w");
        forever begin
            @(negedge uart_tx);
            if(rst_n) begin
                #4340; if(uart_tx!==0) $fatal(1,"TX start bit");
                for(integer n=0;n<8;n=n+1) begin #8680; b[n]=uart_tx; end
                #8680; if(uart_tx!==1) $fatal(1,"TX stop bit");
                received[cursor]=b; cursor=cursor+1;
                if(cursor==83) begin
                    if(!expect_frame || {received[0],received[1],received[2],received[3]}!==32'ha55a0101 ||
                       {received[7],received[6]}!==73 || received[8]!==12 || {received[5],received[4]}!==seq[15:0])
                        $fatal(1,"TX header/count/sequence");
                    crc=16'hffff; for(integer n=2;n<81;n=n+1) crc=crc_step(crc,received[n]);
                    if({received[82],received[81]}!==crc) $fatal(1,"TX CRC");
                    for(integer n=0;n<12;n=n+1) begin
                        if(received[9+6*n]!==8'(n<6 ? n+1 : n<9 ? n+10 : n+23) || received[10+6*n]!==((n==1 || n==3 || n==4) ? 8'h01 : 8'h03))
                            $fatal(1,"TX unexpected ID/type");
                        bits={received[14+6*n],received[13+6*n],received[12+6*n],received[11+6*n]};
                        if(bits!==expected_fields[n]) $fatal(1,"TX snapshot field %0d",n);
                    end
                    for(integer n=0;n<83;n=n+1) $fwrite(hex_file,"%02x ",received[n]);
                    $fwrite(hex_file,"\n"); frames=frames+1; seq=seq+1; cursor=0; expect_frame=0;
                end
            end
        end
    end
    task automatic uart_byte(input [7:0] value);
        begin uart_rx=0; #8680; for(integer n=0;n<8;n=n+1) begin uart_rx=value[n]; #8680; end uart_rx=1; #8680; end
    endtask
    task automatic write_param(input [7:0] id,input [7:0] kind,input [31:0] value,input bad_crc);
        reg [7:0] packet [0:15]; reg [15:0] c;
        begin
            packet[0]=8'ha5; packet[1]=8'h5a; packet[2]=1; packet[3]=8'h10;
            packet[4]=8'h34; packet[5]=8'h12; packet[6]=6; packet[7]=0;
            packet[8]=id; packet[9]=kind; packet[10]=value[7:0]; packet[11]=value[15:8]; packet[12]=value[23:16]; packet[13]=value[31:24];
            c=16'hffff; for(integer n=2;n<14;n=n+1) c=crc_step(c,packet[n]); if(bad_crc) c=c^16'h0100;
            packet[14]=c[7:0]; packet[15]=c[15:8];
            for(integer n=0;n<16;n=n+1) $fwrite(command_file,"%02x ",packet[n]); $fwrite(command_file,"\n");
            @(negedge clk); for(integer n=0;n<16;n=n+1) uart_byte(packet[n]); repeat(15) @(negedge clk);
        end
    endtask
    task automatic pulse(input [2:0] mask);
        begin @(negedge clk); events=mask; @(negedge clk); events=0; end
    endtask
    task automatic wait_ms(input integer count);
        begin repeat(count) begin @(posedge dut.ms_tick); @(posedge clk); @(negedge clk); end repeat(5) @(negedge clk); end
    endtask
    task automatic sample_judge(input [11:0] value);
        begin sensor_angle=value; wait_ms(40); end
    endtask
    task automatic drain;
        begin wait(!dut.tx_busy && !expect_frame && !dut.send_en); repeat(5) @(negedge clk); end
    endtask

    initial begin
        updates[0]=0; updates[1]=0; force dut.key_press=events;
        repeat(5) @(negedge clk); rst_n=1; wait_ms(3);
        if(dut.adc_data!==3000 || !dut.sensor_ok || dut.run_state!==0 || dut.PWM!==0) $fatal(1,"ADC/default stop");
        if(dut.a_kp!==19661 || dut.a_ki!==655 || dut.a_kd!==26214 || dut.p_kp!==26214 || dut.p_ki!==1049 || dut.p_kd!==262144)
            $fatal(1,"PID defaults");
        // Physical quadrature count and sign.
        ab=1; repeat(6) @(negedge clk); ab=3; repeat(6) @(negedge clk); ab=2; repeat(6) @(negedge clk); ab=0; repeat(6) @(negedge clk);
        if(dut.position_cnt!==4) $fatal(1,"Encoder positive direction");
        // Start sequence and 100ms timing from the source (one dispatch ms between stages).
        pulse(4); wait_ms(1); if(dut.run_state!==22 || dut.PWM!==875 || {tb_in1,tb_in2}!==2'b01 || dut.position_offset!==4 || dut.target_position!==0) $fatal(1,"First kick/start origin");
        wait_ms(99); if(dut.run_state!==22) $fatal(1,"Kick ended too early");
        wait_ms(1); if(dut.run_state!==23) $fatal(1,"First kick timer");
        wait_ms(1); if(dut.run_state!==24 || dut.PWM!==-875 || {tb_in1,tb_in2}!==2'b10) $fatal(1,"Reverse kick");
        wait_ms(100); if(dut.run_state!==1 || dut.PWM!==0) $fatal(1,"Kick completion");
        // Three fresh 40ms samples identify right-side minimum, then repeat kick.
        sample_judge(3100); sample_judge(2900); sample_judge(3050);
        if(dut.run_state!==21) $fatal(1,"Right peak detector");
        pulse(4); wait_ms(1); if(dut.run_state!==0 || dut.PWM!==0) $fatal(1,"Stop during swing");
        // Left peak branch without spending another full kick in the simulation.
        @(negedge clk); dut.run_state=1; dut.judge_count=0; dut.history_count=0;
        sample_judge(900); sample_judge(1100); sample_judge(950);
        if(dut.run_state!==31) $fatal(1,"Left peak detector");
        wait_ms(1); if(dut.run_state!==32 || dut.PWM!==-875) $fatal(1,"Left branch kick");
        pulse(4);
        // Move during swing and set a nonzero goal; capture must preserve start origin/goal.
        ab=1; repeat(6) @(negedge clk); ab=3; repeat(6) @(negedge clk); ab=2; repeat(6) @(negedge clk); ab=0; repeat(6) @(negedge clk);
        pulse(1);
        @(negedge clk); dut.run_state=1; dut.judge_count=0; dut.history_count=0;
        sample_judge(2060); if(dut.run_state!==1) $fatal(1,"Captured after only one sample");
        sample_judge(2060); if(dut.run_state!==4 || dut.position_offset!==4 || dut.target_position!==34 || dut.position_feedback!==4 || dut.position_sample!==4) $fatal(1,"Capture changed start origin/goal/feedback");
        wait_ms(55); if(dut.p_out!==12 || dut.a_goal!==2048 || dut.position_pid.d_out!==0 || dut.position_pid.i_term_q!==72'sd31470) $fatal(1,"Capture derivative/default outer integral");
        wait_ms(50); if(updates[0]<20 || updates[1]<2 || dut.position_feedback!==4 || dut.target_position!==34) $fatal(1,"Loop cadence/start origin/goal");
        // The fixed origin includes swing displacement; returning there restores real=0.
        pulse(2); wait_ms(100);
        if(dut.p_out!==-1 || dut.a_goal!==2061) $fatal(1,"Outer PID ignored swing displacement");
        ab=2; repeat(6) @(negedge clk); ab=3; repeat(6) @(negedge clk); ab=1; repeat(6) @(negedge clk); ab=0; repeat(6) @(negedge clk);
        wait_ms(100);
        if(dut.position_feedback!==0 || dut.p_out!==0 || dut.position_offset!==4) $fatal(1,"Return to start origin");
        // Target buttons and cascade sign through two independent original cores.
        pulse(1); wait_ms(50);
        if(dut.target_position!==34 || dut.p_out!==32'd100 || dut.a_goal!==32'd1960) $fatal(1,"Cascade subtraction");
        pulse(2); wait_ms(100);
        if(dut.target_position!==0) $fatal(1,"Negative target key");
        for(integer n=0;n<122;n=n+1) pulse(1);
        if(dut.target_position!==4080) $fatal(1,"Positive goal clamp");
        for(integer n=0;n<242;n=n+1) pulse(2);
        if(dut.target_position!==-4080) $fatal(1,"Negative goal clamp");
        pulse(3); if(dut.target_position!==-4080) $fatal(1,"Simultaneous keys");
        @(negedge clk); dut.target_position=0;
        // Both gain groups over real RX, and invalid commands must not change any gains.
        write_param(8'h10,3,32'd65536,0); write_param(8'h11,3,32'd32768,0); write_param(8'h12,3,32'hffff8000,0);
        write_param(8'h20,3,32'd16384,0); write_param(8'h21,3,32'd655,0); write_param(8'h22,3,32'd131072,0);
        if(dut.a_kp!==65536 || dut.a_ki!==32768 || dut.a_kd!==-32768 || dut.p_kp!==16384 || dut.p_ki!==655 || dut.p_kd!==131072) $fatal(1,"Six gain writes");
        write_param(8'h10,3,32'd131072,1); write_param(8'h10,1,32'd131072,0);
        write_param(8'h01,3,32'd131072,0); write_param(8'h23,3,32'd131072,0);
        if(dut.a_kp!==65536 || dut.p_kp!==16384 || dut.a_goal!==2060) $fatal(1,"Rejected command changed controls");
        // Numerically exercise nonzero errors, fractional I, positive/negative bounds.
        sensor_angle=2070; wait_ms(30); sensor_angle=2050; wait_ms(30);
        write_param(8'h11,3,0,0); wait_ms(5);
        if(dut.angle_pid.i_term_q!==0) $fatal(1,"Gain update did not clear integral");
        write_param(8'h10,3,32'd19660800,0); sensor_angle=2460; wait_ms(10);
        if(dut.a_out!==-100 || dut.PWM!==-2500) $fatal(1,"Negative PID clamp");
        sensor_angle=1660; wait_ms(10);
        if(dut.a_out!==100 || dut.PWM!==2500) $fatal(1,"Positive PID clamp");
        // Boundary is exclusive: motor gate drops before next ms, then state stops.
        sensor_angle=2560; wait_ms(1);
        if(dut.PWM!==0) $fatal(1,"Fall motor gate");
        wait_ms(1); if(dut.run_state!==0 || dut.a_out!==0 || dut.p_out!==0) $fatal(1,"Fall stop");
        // ADC freshness watchdog and no start without fresh data.
        force dut.adc_valid=0; wait_ms(4); pulse(4);
        if(dut.sensor_ok || dut.run_state!==0 || dut.PWM!==0) $fatal(1,"ADC watchdog/start interlock");
        release dut.adc_valid; wait_ms(1);
        drain; @(negedge clk); rst_n=0; repeat(5) @(negedge clk);
        if(dut.run_state!==0 || dut.target_position!==0 || dut.a_kp!==19661 || dut.p_kp!==26214 || dut.p_ki!==1049 || dut.PWM!==0) $fatal(1,"Reset restoration");
        if(frames<20 || adc_frames<100) $fatal(1,"Insufficient telemetry/ADC coverage");
        $fclose(hex_file); $fclose(command_file);
        $display("PASS: %0d/%0d angle/position PID updates, %0d physical UART frames; ADC SPI, 1/5/40/50ms timing, both swing branches, capture, cascade, six gain writes, CRC/type/ID rejection, limits, fall, watchdog, reset",updates[0],updates[1],frames);
        $finish;
    end
    initial begin #1500000000; $fatal(1,"Pendulum test timeout"); end
endmodule
