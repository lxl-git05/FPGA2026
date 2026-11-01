`timescale 1ns / 1ps
// Unsigned magnitude multiply/divide across clocks. Symmetric rounding, signed32 result.
module gain_convert(input wire clk,rst_n,start,
    input wire signed [63:0] value_micro, input wire [63:0] numerator,denominator,
    output reg busy,done,range_error, output reg signed [31:0] result);
    reg negative;
    reg [2:0] state;
    reg [7:0] count;
    reg [127:0] acc,term,dividend,quotient;
    reg [63:0] factor,divisor,remainder;
    wire [127:0] add_next=acc+(factor[0]?term:128'd0);
    wire [64:0] trial={remainder,dividend[127]};
    wire [65:0] sub={1'b0,trial}-{2'b0,divisor};
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            state<=0; busy<=0; done<=0; range_error<=0; result<=0;
            negative<=0; count<=0; acc<=0; term<=0; factor<=0;
            dividend<=0; quotient<=0; divisor<=1; remainder<=0;
        end else begin
            done<=0;
            case(state)
                0: if(start) begin
                    negative<=value_micro[63];
                    term<={64'b0,(value_micro[63]?(~value_micro+64'd1):value_micro)};
                    factor<=numerator; divisor<=denominator;
                    acc<=0; count<=63; busy<=1; range_error<=0; state<=1;
                end
                1: begin
                    acc<=add_next; term<=term<<1; factor<=factor>>1;
                    if(count==0) state<=2; else count<=count-1'b1;
                end
                2: begin
                    dividend<=acc+{64'b0,(divisor>>1)}; quotient<=0; remainder<=0;
                    count<=127; state<=3;
                end
                3: begin
                    dividend<=dividend<<1;
                    remainder<=sub[65]?trial[63:0]:sub[63:0];
                    quotient<={quotient[126:0],!sub[65]};
                    if(count==0) state<=4; else count<=count-1'b1;
                end
                4: begin
                    range_error<=(divisor==0)||(quotient>(negative?128'd2147483648:128'd2147483647));
                    result<=negative?-$signed(quotient[31:0]):$signed(quotient[31:0]);
                    done<=1; busy<=0; state<=0;
                end
                default: begin state<=0; busy<=0; end
            endcase
        end
    end
endmodule
