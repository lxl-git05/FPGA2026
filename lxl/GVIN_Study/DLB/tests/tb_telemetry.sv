`timescale 1ns/1ps
module tb_telemetry;
    reg clk=0,rst_n=0,send=0;
    always #10 clk=~clk;
    reg signed [31:0] ag=2180,ar=2181,aset=-1250,bg=1040,br=-2,bset=-5;
    wire [7:0] data; wire tx_send,done,uart,busy;
    reg [7:0] observed;
    string line="";
    telemetry_tx formatter(.clk(clk),.rst_n(rst_n),.send_frame(send),.tx_done(done),
        .a_goal(ag),.a_real(ar),.a_set_ticks(aset),.b_goal(bg),.b_real(br),.b_set_adc(bset),
        .tx_data(data),.tx_send(tx_send),.busy(busy));
    uart_byte_tx byte_tx(.clk(clk),.rst_n(rst_n),.data_byte(data),.send_en(tx_send),
        .baud_set(3'd4),.uart_tx(uart),.tx_done(done),.uart_state());
    initial begin
        repeat(4) @(negedge clk); rst_n=1;
        @(negedge clk); send=1; @(negedge clk); send=0;
        // All live fields change during transmission; line must keep its original snapshot.
        ag=1; ar=2; aset=3; bg=4; br=5; bset=6;
    end
    initial forever begin
        @(negedge uart); #4340;
        if(uart!==0) $fatal(1,"bad start");
        for(integer j=0;j<8;j++) begin #8680; observed[j]=uart; end
        #8680; if(uart!==1) $fatal(1,"bad stop");
        line={line,observed};
        if(observed==8'h0a) begin
            if(line!="2180.000000,2181.000000,-50.000000,1040.000000,-2.000000,-5.000000\r\n")
                $fatal(1,"unexpected actual UART line [%s]",line);
            $display("PASS six-field physical UART snapshot/CRLF"); $finish;
        end
    end
    initial begin #20000000; $fatal(1,"telemetry did not fit 20ms"); end
endmodule
