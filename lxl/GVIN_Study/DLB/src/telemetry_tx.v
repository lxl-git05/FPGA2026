`timescale 1ns / 1ps
// Latest complete A/B tuples are snapshotted together; the loops have different periods.
// A.set ticks -> percent micro-units (*40000). Other fields are integer code/count (*1e6).
module telemetry_tx(input wire clk,rst_n,send_frame,tx_done,
    input wire signed [31:0] a_goal,a_real,a_set_ticks,b_goal,b_real,b_set_adc,
    output reg [7:0] tx_data,output reg tx_send,output wire busy);

    localparam [3:0] F_IDLE=0, F_LOAD=1, F_REAL_DIV=2, F_BCD_LOAD=3, F_BCD=4,
                     F_SIGN=5, F_DIGIT=6, F_WAIT_DIGIT=7, F_DOT=8,
                     F_SEPARATOR=9, F_LF=10, F_WAIT_LF=11, F_WAIT_SIGN=12,
                     F_WAIT_DOT=13, F_WAIT_SEPARATOR=14;
    reg [3:0] format_state;
    assign busy=(format_state!=0);
    reg [2:0] field_index;
    reg signed [31:0] frame[0:5];
    wire signed [31:0] selected=frame[field_index];
    wire [31:0] magnitude=selected[31]?(~selected+32'd1):selected;
    reg [63:0] micro_acc,micro_term;
    reg [19:0] micro_factor;
    wire [63:0] micro_next=micro_acc+(micro_factor[0]?micro_term:64'd0);

    reg field_negative;
    reg [63:0] field_micro;
    reg [5:0] format_count;
    reg [143:0] bcd_shift, bcd_adjusted;
    wire [143:0] bcd_next = bcd_adjusted << 1;
    reg [79:0] decimal_digits;
    reg [4:0] digit_index;
    reg digit_started, dot_sent;
    integer digit;
    always @(*) begin
        bcd_adjusted = bcd_shift;
        for (digit=0; digit<20; digit=digit+1)
            if (bcd_shift[64+digit*4 +: 4] >= 5)
                bcd_adjusted[64+digit*4 +: 4] = bcd_shift[64+digit*4 +: 4] + 4'd3;
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            format_state <= F_IDLE; frame[0]<=0; frame[1]<=0; frame[2]<=0; frame[3]<=0; frame[4]<=0; frame[5]<=0;
            micro_acc<=0; micro_term<=0; micro_factor<=0;
            field_index <= 0; field_negative <= 0; field_micro <= 0;
            format_count <= 0;
            bcd_shift <= 0; decimal_digits <= 0; digit_index <= 0; digit_started <= 0;
            dot_sent <= 0; tx_data <= 0; tx_send <= 0;
        end else begin
            tx_send <= 0;
            case (format_state)
                F_IDLE: if(send_frame) begin
                    frame[0]<=a_goal; frame[1]<=a_real; frame[2]<=a_set_ticks;
                    frame[3]<=b_goal; frame[4]<=b_real; frame[5]<=b_set_adc;
                    field_index<=0; format_state<=F_LOAD;
                end
                F_LOAD: begin
                    field_negative<=selected[31]; micro_acc<=0; micro_term<={32'b0,magnitude};
                    micro_factor<=(field_index==2)?20'd40000:20'd1000000;
                    format_count<=19; format_state<=F_REAL_DIV;
                end
                F_REAL_DIV: begin
                    micro_acc<=micro_next; micro_term<=micro_term<<1; micro_factor<=micro_factor>>1;
                    if(format_count==0) begin field_micro<=micro_next; format_state<=F_BCD_LOAD; end
                    else format_count<=format_count-1'b1;
                end
                F_BCD_LOAD: begin
                    bcd_shift <= {80'b0, field_micro}; format_count <= 63;
                    digit_index <= 0; digit_started <= 0; dot_sent <= 0;
                    format_state <= F_BCD;
                end
                F_BCD: begin
                    bcd_shift <= bcd_next;
                    if (format_count == 0) begin decimal_digits <= bcd_next[143:64]; format_state <= F_SIGN; end
                    else format_count <= format_count - 1'b1;
                end
                F_SIGN: begin
                    if (field_negative && (field_micro != 0)) begin
                        tx_data <= "-"; tx_send <= 1; format_state <= F_WAIT_SIGN;
                    end else format_state <= F_DIGIT;
                end
                F_WAIT_SIGN: if (tx_done) format_state <= F_DIGIT;
                F_DIGIT: begin
                    if ((digit_index == 14) && !dot_sent) format_state <= F_DOT;
                    else if (!digit_started && (digit_index < 13) && (decimal_digits[79:76] == 0)) begin
                        decimal_digits <= decimal_digits << 4; digit_index <= digit_index + 1'b1;
                    end else begin
                        tx_data <= 8'h30 + {4'b0, decimal_digits[79:76]};
                        tx_send <= 1; digit_started <= 1; format_state <= F_WAIT_DIGIT;
                    end
                end
                F_WAIT_DIGIT: if (tx_done) begin
                    if (digit_index == 19) format_state <= F_SEPARATOR;
                    else begin
                        decimal_digits <= decimal_digits << 4; digit_index <= digit_index + 1'b1;
                        format_state <= F_DIGIT;
                    end
                end
                F_DOT: begin tx_data <= "."; tx_send <= 1; dot_sent <= 1; format_state <= F_WAIT_DOT; end
                F_WAIT_DOT: if (tx_done) format_state <= F_DIGIT;
                F_SEPARATOR: begin
                    tx_data <= (field_index == 5) ? 8'h0d : 8'h2c;
                    tx_send <= 1; format_state <= F_WAIT_SEPARATOR;
                end
                F_WAIT_SEPARATOR: if (tx_done) begin
                    if (field_index == 5) format_state <= F_LF;
                    else begin field_index <= field_index + 1'b1; format_state <= F_LOAD; end
                end
                F_LF: begin tx_data <= 8'h0a; tx_send <= 1; format_state <= F_WAIT_LF; end
                F_WAIT_LF: if (tx_done) format_state <= F_IDLE;
                default: format_state <= F_IDLE;
            endcase
        end
    end
endmodule
