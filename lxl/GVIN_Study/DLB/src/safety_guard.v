`timescale 1ns / 1ps
// The swing-up region and the balance region deliberately have different permissions.
// fault_now is independent of PID completion; final motor gate consumes it directly.
module safety_guard #(parameter integer ADC_RANGE_ONLY=0)(input wire clk,rst_n,ms_tick,active,balancing,
    input wire raw_valid,raw_otr,angle_valid,balance_sample_valid,
    input wire [11:0] balance_angle_adc,
    input wire [11:0] raw_adc,angle_adc,rail_low,rail_high,capture_adc,fall_adc,
    input wire signed [31:0] center_adc,position_count,
    input wire [31:0] travel_counts, input wire [15:0] adc_timeout_ms,
    output wire sensor_ok,capture_allowed,balance_safe,position_safe,
    output wire fault_now, output wire [3:0] fault_reason);
    reg seen;
    reg [15:0] age_ms;
    wire signed [32:0] position_ext={position_count[31],position_count};
    wire [32:0] position_abs=position_ext[32]?-position_ext:position_ext;
    wire signed [12:0] balance_error=$signed({1'b0,balance_angle_adc})-$signed({1'b0,center_adc[11:0]});
    wire signed [12:0] mean_error=$signed({1'b0,angle_adc})-$signed({1'b0,center_adc[11:0]});
    wire [12:0] balance_abs=balance_error[12]?-balance_error:balance_error;
    wire [12:0] mean_abs=mean_error[12]?-mean_error:mean_error;
    wire raw_in_range=(raw_adc>rail_low)&&(raw_adc<rail_high);
    // The mechanical blind zone can drive OTR at zero/full scale. It must not
    // prevent the initial kick. Only non-balancing rail samples get this exception;
    // OTR in the usable range and ALL balancing OTR samples remain faults.
    wire otr_fault=raw_otr&&(balancing||raw_in_range);
    assign sensor_ok=ADC_RANGE_ONLY?seen:seen&&(age_ms<adc_timeout_ms)&&!otr_fault;
    assign position_safe=position_abs<={1'b0,travel_counts};
    assign capture_allowed=sensor_ok&&(ADC_RANGE_ONLY||(angle_valid&&raw_in_range))&&(mean_abs<=capture_adc);
    // Range protection uses each inner-loop feedback snapshot, not isolated raw samples.
    assign balance_safe=sensor_ok&&(ADC_RANGE_ONLY||(angle_valid&&raw_in_range))&&(!balance_sample_valid||(balance_abs<=fall_adc));
    assign fault_reason=!sensor_ok?(otr_fault?4'd2:4'd1):
                        !position_safe?4'd3:(balancing&&!balance_safe)?4'd4:4'd0;
    assign fault_now=active&&(fault_reason!=0);
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin seen<=0; age_ms<=0; end
        else if(raw_valid) begin seen<=1; age_ms<=0; end
        else if(ms_tick && age_ms!=16'hffff) age_ms<=age_ms+1'b1;
    end
endmodule
