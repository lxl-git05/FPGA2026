`timescale 1ns / 1ps
// 自检：默认1ms更新、平均末样本、满量程、OTR、真实UART位及发送期间快照冻结。
module adc_uart_tb;
    reg clk = 0;
    always #10 clk = ~clk;
    reg rst_n = 0;
    reg [9:0] adc_data_in = 0;
    reg adc_otr = 0;
    wire adc_clk, adc_oe_n, uart_tx;
    integer cycle_count = 0, last_valid = 0, valid_count = 0;
    reg previous_valid = 0;
    reg [11:0] previous_data = 0;
    top dut (
        .clk(clk), .rst_n(rst_n), .adc_data_in(adc_data_in), .adc_otr(adc_otr),
        .adc_clk(adc_clk), .adc_oe_n(adc_oe_n), .uart_tx(uart_tx)
    );

    always @(posedge clk) begin
        if (!rst_n) begin
            cycle_count = 0; last_valid = 0; valid_count = 0;
            previous_valid = 0; previous_data = 0;
        end else begin
            cycle_count = cycle_count + 1;
            #1;
            if (dut.adc_valid) begin
                if (previous_valid) $fatal(1, "valid wider than one clock");
                if (cycle_count - last_valid != 50000) $fatal(1, "Update is not 1ms");
                last_valid = cycle_count;
                valid_count = valid_count + 1;
            end else if (dut.adc_value !== previous_data) $fatal(1, "Data changed without valid");
            previous_valid = dut.adc_valid;
            previous_data = dut.adc_value;
        end
    end

    task automatic check_result(input integer value, input integer raw, input integer over);
        begin
            @(posedge dut.adc_valid); #2;
            if (dut.adc_value !== value || dut.adc_raw !== raw || dut.adc_over !== over)
                $fatal(1, "ADC value=%d raw=%d over=%b expected=%d/%d/%d",
                       dut.adc_value, dut.adc_raw, dut.adc_over, value, raw, over);
            @(negedge clk);
        end
    endtask

    localparam integer BIT_NS = 434 * 20;
    task automatic receive_byte(output reg [7:0] value);
        integer i;
        begin
            @(negedge uart_tx);
            #(BIT_NS + BIT_NS/2);
            for (i = 0; i < 8; i = i + 1) begin
                value[i] = uart_tx;
                #(BIT_NS);
            end
            if (uart_tx !== 1'b1) $fatal(1, "UART stop bit");
        end
    endtask

    string expected;
    reg [7:0] received;
    integer line, index;
    initial begin
        repeat (5) @(negedge clk);
        if (adc_oe_n !== 1 || uart_tx !== 1) $fatal(1, "Reset outputs");
        rst_n = 1;
        check_result(0, 0, 0);
        adc_data_in = 512;
        check_result(2048, 512, 0);
        adc_data_in = 1023;
        adc_otr = 1;
        check_result(4092, 1023, 1);
        adc_data_in = 0;
        adc_otr = 0;
        // 前15个样本为0，仅窗口最后一个样本为1023，均值floor(4092/16)=255。
        #950000;
        adc_data_in = 1023;
        adc_otr = 1;
        check_result(255, 1023, 1);
        adc_data_in = 515;
        adc_otr = 0;
        check_result(2060, 515, 0);

        for (line = 0; line < 2; line = line + 1) begin
            wait (dut.state == 3);
            expected = {$sformatf("adc=%04d,raw=%04d,otr=%0d,seq=%010d,update_us=001000",
                                  dut.frame_adc, dut.frame_raw, dut.frame_otr, dut.frame_seq), 8'h0d, 8'h0a};
            if (expected.len() != 57) $fatal(1, "Text length");
            for (index = 0; index < 57; index = index + 1) begin
                receive_byte(received);
                if (received !== expected[index])
                    $fatal(1, "Line %0d byte %0d got=%h expected=%h", line, index, received, expected[index]);
                // 在第一行发送中改变输入，后续ADC更新不得改变这行快照。
                if (line == 0 && index == 1) begin adc_data_in = 100; adc_otr = 1; end
            end
        end
        if (valid_count < 200) $fatal(1, "ADC stalled while transmitting");
        @(negedge clk); rst_n = 0; #1;
        if (adc_oe_n !== 1 || dut.adc_value !== 0) $fatal(1, "Reset recovery");
        $display("PASS: ADC 1ms/16 samples, final sample, OTR, full scale, UART text and frozen snapshots");
        $finish;
    end
    initial begin #220000000; $fatal(1, "Timeout"); end
endmodule
