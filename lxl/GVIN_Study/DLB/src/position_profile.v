`timescale 1ns / 1ps
// One-revolution position reference generator for the K2 command.
//
// Profile (u = t/T, 0..1):
//   position s(t) = REV * (3u^2 - 2u^3)        (cubic, s(0)=0, s(T)=REV)
//   velocity v(t) = (6*REV/T) * u * (1-u)      (quadratic, v(0)=v(T)=0)
//   peak velocity = 1.5*REV/T
// With REV=1040:
//   T=3000ms: peak=520 counts/s (default; 60 steps of 50ms; max step 26 counts)
//   T=3000ms: peak=520 counts/s (30 steps of 100ms; previous setting)
//   T=1500ms: peak=1040 counts/s (30 steps of 50ms)
//   T=3000ms: peak=520 counts/s (20 steps of 150ms; oldest setting)
//   T=1000ms: peak=1560 counts/s (20 steps of 50ms)
//   T= 600ms: peak=2600 counts/s (12 steps of 50ms)
//   T= 500ms: peak=3120 counts/s (10 steps of 50ms)
// For 520 counts/s with 50ms updates, T = 3.0s and the 60-point table below
// is used. N=60, max step 26 counts, 26/0.05s = 520 counts/s. The outer 50ms
// loop sees a new target every tick.
//
// The 60-step staircase (T=3000ms, 50ms per step):
//   0,1,3,8,13,20,29,39,51,63,77,92,108,125,143,162,182,203,225,247,
//   270,293,317,341,366,391,417,442,468,494,520,546,572,598,623,649,
//   674,699,723,747,770,793,815,837,858,878,897,915,932,948,963,977,
//   989,1001,1011,1020,1027,1032,1037,1039,1040
// The maximum step is 26 counts/50ms = 520 counts/s.
//
// move_target is an absolute position-loop target. On start it is latched to
// the actual position_count, then advances one revolution. After the last step
// move_hold stays high so the outer PID holds the new position. A new start
// begins another revolution from the then-current actual position.
module position_profile #(
    parameter integer COUNTS_PER_REV=1040,
    parameter integer MOVE_SIGN=1,       // +1: +one revolution, -1: -one revolution
    parameter integer STEP_MS=50,        // 50ms matches the default outer-loop period
    parameter integer MOVE_TIME_MS=3000, // 60 points at 50ms -> peak 520 counts/s
    parameter integer MAX_SPEED_COUNTS_PER_S=520
)(
    input wire clk,rst_n,ms_tick,
    input wire start,                    // one-clock pulse, already gated to BALANCE
    input wire abort,                    // leave BALANCE / fault / auto_retry
    input wire signed [31:0] position_count,
    input wire signed [31:0] goal_position,
    output reg signed [31:0] move_target,
    output reg move_active,
    output reg move_hold
);
    localparam integer N=MOVE_TIME_MS/STEP_MS;
    localparam integer VMAX_COUNTS_PER_S=(3*COUNTS_PER_REV*1000)/(2*MOVE_TIME_MS);
    localparam integer MIN_TIME_MS=(3*COUNTS_PER_REV*1000)/(2*MAX_SPEED_COUNTS_PER_S);

    // Sampled cubic position profile s(u)=REV*(3u^2-2u^3), u=k/N.
    function [11:0] profile;
        input [5:0] k;
        begin
            if(N==10) begin
                case(k)
                    5'd0:  profile=12'd0;
                    5'd1:  profile=12'd29;
                    5'd2:  profile=12'd108;
                    5'd3:  profile=12'd225;
                    5'd4:  profile=12'd366;
                    5'd5:  profile=12'd520;
                    5'd6:  profile=12'd674;
                    5'd7:  profile=12'd815;
                    5'd8:  profile=12'd932;
                    5'd9:  profile=12'd1011;
                    5'd10: profile=12'd1040;
                    default: profile=12'd1040;
                endcase
            end else if(N==12) begin
                case(k)
                    5'd0:  profile=12'd0;
                    5'd1:  profile=12'd20;
                    5'd2:  profile=12'd77;
                    5'd3:  profile=12'd163;
                    5'd4:  profile=12'd270;
                    5'd5:  profile=12'd391;
                    5'd6:  profile=12'd520;
                    5'd7:  profile=12'd649;
                    5'd8:  profile=12'd770;
                    5'd9:  profile=12'd878;
                    5'd10: profile=12'd963;
                    5'd11: profile=12'd1020;
                    5'd12: profile=12'd1040;
                    default: profile=12'd1040;
                endcase
            end else if(N==30) begin
                case(k)
                    5'd0:  profile=12'd0;
                    5'd1:  profile=12'd3;
                    5'd2:  profile=12'd13;
                    5'd3:  profile=12'd29;
                    5'd4:  profile=12'd51;
                    5'd5:  profile=12'd77;
                    5'd6:  profile=12'd108;
                    5'd7:  profile=12'd143;
                    5'd8:  profile=12'd182;
                    5'd9:  profile=12'd225;
                    5'd10: profile=12'd270;
                    5'd11: profile=12'd317;
                    5'd12: profile=12'd366;
                    5'd13: profile=12'd417;
                    5'd14: profile=12'd468;
                    5'd15: profile=12'd520;
                    5'd16: profile=12'd572;
                    5'd17: profile=12'd623;
                    5'd18: profile=12'd674;
                    5'd19: profile=12'd723;
                    5'd20: profile=12'd770;
                    5'd21: profile=12'd815;
                    5'd22: profile=12'd858;
                    5'd23: profile=12'd897;
                    5'd24: profile=12'd932;
                    5'd25: profile=12'd963;
                    5'd26: profile=12'd989;
                    5'd27: profile=12'd1011;
                    5'd28: profile=12'd1027;
                    5'd29: profile=12'd1037;
                    5'd30: profile=12'd1040;
                    default: profile=12'd1040;
                endcase
            end else if(N==60) begin
                case(k)
                    6'd0:  profile=12'd0;
                    6'd1:  profile=12'd1;
                    6'd2:  profile=12'd3;
                    6'd3:  profile=12'd8;
                    6'd4:  profile=12'd13;
                    6'd5:  profile=12'd20;
                    6'd6:  profile=12'd29;
                    6'd7:  profile=12'd39;
                    6'd8:  profile=12'd51;
                    6'd9:  profile=12'd63;
                    6'd10: profile=12'd77;
                    6'd11: profile=12'd92;
                    6'd12: profile=12'd108;
                    6'd13: profile=12'd125;
                    6'd14: profile=12'd143;
                    6'd15: profile=12'd162;
                    6'd16: profile=12'd182;
                    6'd17: profile=12'd203;
                    6'd18: profile=12'd225;
                    6'd19: profile=12'd247;
                    6'd20: profile=12'd270;
                    6'd21: profile=12'd293;
                    6'd22: profile=12'd317;
                    6'd23: profile=12'd341;
                    6'd24: profile=12'd366;
                    6'd25: profile=12'd391;
                    6'd26: profile=12'd417;
                    6'd27: profile=12'd442;
                    6'd28: profile=12'd468;
                    6'd29: profile=12'd494;
                    6'd30: profile=12'd520;
                    6'd31: profile=12'd546;
                    6'd32: profile=12'd572;
                    6'd33: profile=12'd598;
                    6'd34: profile=12'd623;
                    6'd35: profile=12'd649;
                    6'd36: profile=12'd674;
                    6'd37: profile=12'd699;
                    6'd38: profile=12'd723;
                    6'd39: profile=12'd747;
                    6'd40: profile=12'd770;
                    6'd41: profile=12'd793;
                    6'd42: profile=12'd815;
                    6'd43: profile=12'd837;
                    6'd44: profile=12'd858;
                    6'd45: profile=12'd878;
                    6'd46: profile=12'd897;
                    6'd47: profile=12'd915;
                    6'd48: profile=12'd932;
                    6'd49: profile=12'd948;
                    6'd50: profile=12'd963;
                    6'd51: profile=12'd977;
                    6'd52: profile=12'd989;
                    6'd53: profile=12'd1001;
                    6'd54: profile=12'd1011;
                    6'd55: profile=12'd1020;
                    6'd56: profile=12'd1027;
                    6'd57: profile=12'd1032;
                    6'd58: profile=12'd1037;
                    6'd59: profile=12'd1039;
                    6'd60: profile=12'd1040;
                    default: profile=12'd1040;
                endcase
            end else begin
                case(k)
                    5'd0:  profile=12'd0;
                    5'd1:  profile=12'd8;
                    5'd2:  profile=12'd29;
                    5'd3:  profile=12'd63;
                    5'd4:  profile=12'd108;
                    5'd5:  profile=12'd163;
                    5'd6:  profile=12'd225;
                    5'd7:  profile=12'd293;
                    5'd8:  profile=12'd366;
                    5'd9:  profile=12'd442;
                    5'd10: profile=12'd520;
                    5'd11: profile=12'd598;
                    5'd12: profile=12'd674;
                    5'd13: profile=12'd747;
                    5'd14: profile=12'd815;
                    5'd15: profile=12'd878;
                    5'd16: profile=12'd932;
                    5'd17: profile=12'd977;
                    5'd18: profile=12'd1011;
                    5'd19: profile=12'd1032;
                    5'd20: profile=12'd1040;
                    default: profile=12'd1040;
                endcase
            end
        end
    endfunction

    function signed [32:0] signed_offset;
        input [5:0] k;
        reg [11:0] p;
        begin
            p=profile(k);
            if(MOVE_SIGN<0) signed_offset=-$signed({21'd0,p});
            else            signed_offset= $signed({21'd0,p});
        end
    endfunction

    reg [5:0] step;
    reg [7:0] step_ms;
    reg signed [31:0] start_pos;
    reg signed [31:0] goal_prev;
    wire signed [32:0] start_ext={start_pos[31],start_pos};
    wire signed [32:0] offset_next=signed_offset(step+1'b1);
    wire signed [32:0] sum_next=start_ext+offset_next;

    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            step<=0; step_ms<=0; start_pos<=0; goal_prev<=0;
            move_target<=0; move_active<=0; move_hold<=0;
        end else begin
            if(goal_position!=goal_prev) begin
                // A new goal_B write cancels any K2 hold/move and restores the goal.
                goal_prev<=goal_position;
                move_active<=0; move_hold<=0;
                move_target<=goal_position;
                step<=0; step_ms<=0;
            end else if(abort) begin
                move_active<=0; move_hold<=0;
                move_target<=goal_position;
                step<=0; step_ms<=0;
            end else if(start && !move_active) begin
                // Start the one-revolution move from the actual position.
                start_pos<=position_count;
                move_target<=position_count;
                step<=0; step_ms<=0;
                move_active<=1; move_hold<=0;
            end else if(move_active) begin
                if(ms_tick) begin
                    if(step_ms==STEP_MS-1) begin
                        step_ms<=0;
                        if(step<N) begin
                            step<=step+1'b1;
                            move_target<=(sum_next>33'sd2147483647)?32'sh7fffffff:
                                         (sum_next< -33'sd2147483648)?32'sh80000000:
                                         sum_next[31:0];
                            if(step+1'b1==N) begin
                                move_active<=0;
                                move_hold<=1;
                            end
                        end else begin
                            move_active<=0;
                            move_hold<=1;
                        end
                    end else step_ms<=step_ms+1'b1;
                end
            end
        end
    end
endmodule


