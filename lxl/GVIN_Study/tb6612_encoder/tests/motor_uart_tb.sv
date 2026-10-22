`timescale 1ns / 1ps
// 真实UART引脚自检：分隔符/空闲提交/错误拒收、PWM计数、AB方向和有符号快照。
module motor_uart_tb;
    reg clk = 0;
    always #10 clk = ~clk;
    reg rst_n = 0, uart_rx = 1, encoder_a = 0, encoder_b = 0;
    wire uart_tx, tb_in1, tb_in2, tb_pwm;
    top #(.REPORT_MS(20), .RX_IDLE_MS(1)) dut (
        .clk(clk), .rst_n(rst_n), .encoder_a(encoder_a), .encoder_b(encoder_b),
        .uart_rx(uart_rx), .uart_tx(uart_tx), .tb_in1(tb_in1), .tb_in2(tb_in2), .tb_pwm(tb_pwm)
    );
    task automatic send_byte(input reg [7:0] value);
        integer bit_index;
        begin
            @(negedge clk); uart_rx = 0;
            repeat(434) @(negedge clk);
            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
                uart_rx = value[bit_index];
                repeat(434) @(negedge clk);
            end
            uart_rx = 1;
            repeat(434) @(negedge clk);
        end
    endtask
    task automatic send_text(input string text);
        integer index;
        begin
            for (index = 0; index < text.len(); index = index + 1) send_byte(text[index]);
            repeat(20) @(negedge clk);
        end
    endtask
    task automatic check_command(input integer value);
        begin
            if (dut.motor_command !== value) $fatal(1, "PWM command got=%d expected=%d", dut.motor_command, value);
        end
    endtask
    task automatic check_duty(input integer expected);
        integer index, high_count;
        begin
            repeat(5000) @(negedge clk);
            high_count = 0;
            for (index = 0; index < 2500; index = index + 1) begin
                if (tb_pwm) high_count = high_count + 1;
                @(negedge clk);
            end
            if (high_count != expected) $fatal(1, "PWM high ticks=%d expected=%d", high_count, expected);
        end
    endtask
    task automatic encoder_state(input reg [1:0] value);
        begin
            @(negedge clk); {encoder_a,encoder_b} = value;
            repeat(8) @(negedge clk);
        end
    endtask

    localparam integer BIT_NS = 434 * 20;
    task automatic receive_after_start(output reg [7:0] value);
        integer bit_index;
        begin
            #(BIT_NS + BIT_NS/2);
            for (bit_index = 0; bit_index < 8; bit_index = bit_index + 1) begin
                value[bit_index] = uart_tx;
                #(BIT_NS);
            end
            if (uart_tx !== 1) $fatal(1, "Bad UART stop bit");
        end
    endtask
    string expected;
    reg [7:0] received;
    integer frame_count = 0, byte_index;
    reg line_active = 0, commands_done = 0;
    initial begin
        wait(rst_n);
        forever begin
            @(negedge uart_tx);
            expected = {$sformatf("enc=%s%0d,delta=%s%0d,pwm=%s%0d",
                dut.frame_position[31] ? "-" : "+",
                dut.frame_position[31] ? (~$unsigned(dut.frame_position)+32'd1) : $unsigned(dut.frame_position),
                dut.frame_delta[31] ? "-" : "+",
                dut.frame_delta[31] ? (~$unsigned(dut.frame_delta)+32'd1) : $unsigned(dut.frame_delta),
                dut.frame_pwm[31] ? "-" : "+",
                dut.frame_pwm[31] ? (~$unsigned(dut.frame_pwm)+32'd1) : $unsigned(dut.frame_pwm)), 8'h0d, 8'h0a};
            line_active = 1;
            for (byte_index = 0; byte_index < expected.len(); byte_index = byte_index + 1) begin
                if (byte_index != 0) @(negedge uart_tx);
                receive_after_start(received);
                if (received !== expected[byte_index])
                    $fatal(1, "Telemetry frame=%d byte=%d got=%h expected=%h", frame_count, byte_index, received, expected[byte_index]);
            end
            line_active = 0;
            frame_count = frame_count + 1;
        end
    end

    initial begin
        repeat(5) @(negedge clk); rst_n = 1;
        check_command(0);
        if ({tb_in1,tb_in2,tb_pwm} !== 0) $fatal(1, "Startup not stopped");
        send_text(string'({"20",8'h0d})); check_command(20); check_duty(20);
        send_text(string'({"1250",8'h0a})); check_command(1250); check_duty(1250);
        if ({tb_in1,tb_in2} !== 2'b01) $fatal(1, "Positive clockwise direction");
        send_text(string'({"-2500",8'h0d,8'h0a})); check_command(-2500); check_duty(2500);
        if ({tb_in1,tb_in2} !== 2'b10) $fatal(1, "Negative counterclockwise direction");
        send_text(string'({8'h0d,8'h0a})); check_command(-2500);
        send_text(string'({"2501",8'h0d})); check_command(-2500);
        send_text(string'({"12x",8'h0a})); check_command(-2500);
        send_text(string'({"-",8'h0d})); check_command(-2500);
        send_text(string'({"00000",8'h0d})); check_command(-2500);
        send_text("1250"); check_command(-2500);
        #1100000; check_command(1250);
        send_text(string'({8'h0d,8'h0a})); check_command(1250);
        send_text(string'({"+2500",8'h0d})); check_command(2500);
        send_text(string'({"0",8'h0d,8'h0a})); check_command(0); check_duty(0);
        encoder_state(2'b01); encoder_state(2'b11); encoder_state(2'b10); encoder_state(2'b00);
        if (dut.position_cnt !== -4) $fatal(1, "Raw AB sequence must decrease after reversal");
        repeat(2) begin
            encoder_state(2'b10); encoder_state(2'b11); encoder_state(2'b01); encoder_state(2'b00);
        end
        if (dut.position_cnt !== 4) $fatal(1, "Opposite AB sequence must increase after reversal");
        send_text(string'({"20",8'h0d}));
        // signed32最小值需要输出幅值2147483648，不能被abs截断翻转。
        force dut.encoder_inst.position_cnt = 32'sh80000000;
        wait(line_active);
        send_text(string'({"1250",8'h0d})); check_command(1250);
        commands_done = 1;
        wait(frame_count >= 2);
        release dut.encoder_inst.position_cnt;
        @(negedge clk); rst_n = 0; #1;
        if ({tb_in1,tb_in2,tb_pwm} !== 0) $fatal(1, "Reset must stop immediately");
        $display("PASS: UART delimiters/timeout/rejection, signed PWM/duty, encoder, signed decimal frozen telemetry");
        $finish;
    end
    initial begin #60000000; $fatal(1, "Timeout"); end
endmodule
