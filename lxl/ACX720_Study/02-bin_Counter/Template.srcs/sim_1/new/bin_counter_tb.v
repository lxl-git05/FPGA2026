`timescale 1ns / 1ps
module bin_counter_tb;
    // Parameters

    //Ports
    reg  clk;
    reg  rst_n;
    wire LED;

    bin_counter # (
        .CNT_MAX(25_000)
    )
    bin_counter_inst (
        .clk(clk),
        .rst_n(rst_n),
        .LED(LED)
    );

    always #10  clk = ! clk ;

    initial begin
        clk = 1'b0 ;
        rst_n = 1'b0 ;
        #10 rst_n = 1'b1 ;
    end
endmodule