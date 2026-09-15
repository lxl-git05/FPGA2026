`timescale 1ns / 1ps
module decoder3_8_tb;
    // Parameters
    reg clk ;
    //Ports
    reg rst_n;
    reg [2:0] In;
    wire [7:0] Out;

    decoder3_8  decoder3_8_inst (
        .rst_n(rst_n),
        .In(In),
        .Out(Out)
    );

    always #10  clk = ! clk ;   // 20ns为1个周期

    // 逻辑
    initial begin
        rst_n = 1'b0 ;
        clk = 0 ;
        #10 rst_n = 1'b1 ;
        // 输入改变
        #2 In = 3'b000 ;
        #2 In = 3'b001 ;
        #2 In = 3'b010 ;
        #2 In = 3'b011 ;
        #2 In = 3'b100 ;
        #2 In = 3'b101 ;
        #2 In = 3'b110 ;
        #2 In = 3'b111 ;
        $stop ;
    end

endmodule