`timescale 1ns / 1ps
// Single owner of runtime configuration. All writes use signed micro-units.
// IDs 0..7 are UART PID commands. 80..91(hex) are reserved stopped-only globals.
// Period changes recalculate all three gains transactionally before becoming visible.
// 日常默认配置在下方复位分支，改后需重新综合下载；串口调参在复位后恢复默认值。
module config_bank #(parameter integer COUNTS_PER_REV=1040)(input wire clk,rst_n,stopped,write_valid,
    input wire [7:0] write_id, input wire signed [63:0] write_micro,
    output wire ready,
    output reg dual_loop,
    output reg auto_start,
    output reg [15:0] period_a_ms,
    output reg [15:0] period_b_ms,
    output reg [11:0] capture_adc,
    output reg [11:0] fall_adc,
    output reg [7:0] kick_percent,
    output reg [15:0] kick_ms,
    output reg [15:0] judge_ms,
    output reg [15:0] swing_timeout_ms,
    output reg [15:0] adc_timeout_ms,
    output reg [11:0] rail_low,
    output reg [11:0] rail_high,
    output reg [15:0] outer_limit_adc,
    output reg [7:0] inner_limit_percent,
    output reg [7:0] inner_i_percent,
    output reg [15:0] outer_i_adc,
    output reg [31:0] travel_counts,
    output reg signed [31:0] kp_a,
    output reg signed [31:0] ki_a,
    output reg signed [31:0] kd_a,
    output reg signed [31:0] kp_b,
    output reg signed [31:0] ki_b,
    output reg signed [31:0] kd_b,
    output reg signed [31:0] center_adc,goal_position,
    output reg [31:0] epoch_a,epoch_b);
    reg signed [63:0] gain_micro[0:5];
    reg [2:0] state;
    reg [7:0] pending_id;
    reg signed [63:0] pending_micro,convert_micro;
    reg [63:0] numerator,denominator;
    reg convert_start;
    wire convert_done,convert_error;
    wire signed [31:0] converted;
    reg batch,batch_loop,batch_failed;
    reg [1:0] batch_index;
    reg [15:0] candidate_period;
    reg signed [31:0] batch_result[0:2];
    wire signed [31:0] v=converted;
    wire signed [32:0] value_ext={converted[31],converted};
    wire signed [32:0] center_ext={center_adc[31],center_adc};
    wire signed [32:0] fall_ext=$signed({1'b0,fall_adc});
    wire loop_b=pending_id[2];
    wire [1:0] coefficient=pending_id[1:0];
    assign ready=(state==0);
    function [63:0] default_b_micro;
        input [63:0] value_at_1040;
        begin default_b_micro=(value_at_1040*64'd1040+COUNTS_PER_REV/2)/COUNTS_PER_REV; end
    endfunction
    gain_convert converter(.clk(clk),.rst_n(rst_n),.start(convert_start),
        .value_micro(convert_micro),.numerator(numerator),.denominator(denominator),
        .busy(),.done(convert_done),.range_error(convert_error),.result(converted));
    function [31:0] init_q;
        input [63:0] micro; input integer id;
        reg [127:0] num,den;
        begin
            num=micro*128'd65536*((id<3)?25:1); den=1000000;
            if(id%3==1) begin num=num*((id<3)?5:50); den=1000000000; end
            if(id%3==2) begin num=num*1000; den=1000000*((id<3)?5:50); end
            init_q=(num+den/2)/den;
        end
    endfunction
    task setup_gain;
        input is_b; input [1:0] term_id; input [15:0] period_ms;
        begin
            numerator<=64'd65536*(is_b?1:25); denominator<=1000000;
            if(term_id==1) begin numerator<=64'd65536*(is_b?1:25)*period_ms; denominator<=1000000000; end
            if(term_id==2) begin numerator<=64'd65536*(is_b?1:25)*1000; denominator<=64'd1000000*period_ms; end
        end
    endtask
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            dual_loop <= 1'd1; // 0=单内环、1=双环，切换无需修改PID或直立基准，起摆方式独立设置。
            auto_start <= 1'd1; // 0=手动扶摆、1=自动脉冲起摆，与单双环无关，均需按K1启动。
            period_a_ms <= 16'd5; // 内环周期ms，修改默认值时还需同步init_q函数中的内环周期5。
            period_b_ms <= 16'd50; // 外环周期ms，修改默认值时还需同步init_q函数中的外环周期50。
            capture_adc <= 12'd500; // 捕获区半宽ADC码，应不大于fall_adc且不小于outer_limit_adc。
            fall_adc <= 12'd700; // 稳摆保护半宽ADC码，直立基准±此值须位于两端死区阈值之间。
            kick_percent <= 8'd35; // 自动起摆力度%，范围1~100，手动模式不使用。
            kick_ms <= 16'd100; // 自动起摆每个方向的脉冲时长ms，手动模式不使用。
            judge_ms <= 16'd40; // 峰值与捕获判断间隔ms，连续两次满足捕获条件才进入稳摆。
            swing_timeout_ms <= 16'd10000; // 自动起摆总超时ms，超时停机，手动等待不计此超时。
            adc_timeout_ms <= 16'd3; // ADC原始采样失鲜超时ms，与正常经过端点死区不同。
            rail_low <= 12'd64; // ADC不大于此值视为低端死区，无效角度不参与捕获或稳摆。
            rail_high <= 12'd4032; // ADC不小于此值视为高端死区，实际10位扩展原始最大值4092。
            outer_limit_adc <= 16'd100; // 外环目标修正限幅ADC码，单环自动忽略，无需随模式修改。
            inner_limit_percent <= 8'd100; // 内环输出限幅%，自动起摆力度由kick_percent单独设置。
            inner_i_percent <= 8'd100; // 内环积分项贡献限幅%，不是Ki系数。
            outer_i_adc <= 16'd100; // 外环积分项贡献限幅ADC码，单环自动忽略。
            travel_counts <= 10*COUNTS_PER_REV; // 相对启动原点的行程限幅计数，默认10圈，不跟随外环目标移动。
            // PID数值填实际值×1000000，修改时同步本行两处数值，Q系数自动换算。
            gain_micro[0] <= 64'sd380000; kp_a <= init_q(64'd380000, 0); // 内环Kp=0.380000。
            gain_micro[1] <= 64'sd0; ki_a <= init_q(64'd0, 1); // 内环Ki=0。
            gain_micro[2] <= 64'sd12000; kd_a <= init_q(64'd12000, 2); // 内环Kd=0.012000。
            gain_micro[3] <= default_b_micro(64'd0); kp_b <= init_q(default_b_micro(64'd0), 3); // 外环Kp=0。
            gain_micro[4] <= default_b_micro(64'd0); ki_b <= init_q(default_b_micro(64'd0), 4); // 外环Ki=0。
            gain_micro[5] <= default_b_micro(64'd0); kd_b <= init_q(default_b_micro(64'd0), 5); // 外环Kd=0。
            center_adc<=2180; goal_position<=0; epoch_a<=0; epoch_b<=0; // 前两项为直立ADC基准和电机目标计数，epoch为内部版本号勿改。
            state<=0; pending_id<=0; pending_micro<=0; convert_micro<=0;
            numerator<=1; denominator<=1; convert_start<=0;
            batch<=0; batch_loop<=0; batch_index<=0; candidate_period<=1;
            batch_failed<=0; batch_result[0]<=0; batch_result[1]<=0; batch_result[2]<=0;
        end else begin
            convert_start<=0;
            case(state)
                0: if(write_valid && (write_id<8 || (stopped && write_id>=8'h80 && write_id<=8'h91))) begin
                    pending_id<=write_id; pending_micro<=write_micro; convert_micro<=write_micro;
                    batch<=0;
                    if(write_id<8 && write_id[1:0]!=3)
                        setup_gain(write_id[2],write_id[1:0],write_id[2]?period_b_ms:period_a_ms);
                    else begin numerator<=1; denominator<=1000000; end
                    state<=1;
                end
                1: begin convert_start<=1; state<=2; end
                2: if(convert_done) begin
                    state<=0;
                    if(batch) begin
                        if(convert_error) batch_failed<=1;
                        batch_result[batch_index]<=converted;
                        if(batch_index==2) state<=5;
                        else begin batch_index<=batch_index+1'b1; state<=4; end
                    end else if(!convert_error && !(pending_id[7] && v<0)) begin
                        case(pending_id)
                        8'd0: begin kp_a<=converted; gain_micro[0]<=pending_micro; epoch_a<=epoch_a+1'b1; end
                        8'd1: begin ki_a<=converted; gain_micro[1]<=pending_micro; epoch_a<=epoch_a+1'b1; end
                        8'd2: begin kd_a<=converted; gain_micro[2]<=pending_micro; epoch_a<=epoch_a+1'b1; end
                        8'd4: begin kp_b<=converted; gain_micro[3]<=pending_micro; epoch_b<=epoch_b+1'b1; end
                        8'd5: begin ki_b<=converted; gain_micro[4]<=pending_micro; epoch_b<=epoch_b+1'b1; end
                        8'd6: begin kd_b<=converted; gain_micro[5]<=pending_micro; epoch_b<=epoch_b+1'b1; end
                        8'd3: if(v>0 && v<4092 && value_ext-fall_ext>$signed({1'b0,rail_low}) && value_ext+fall_ext<$signed({1'b0,rail_high})) center_adc<=v;
                        8'd7: if(v<=$signed(travel_counts) && v>=-$signed(travel_counts)) goal_position<=v;
                        8'h80: if(v==0 || v==1) dual_loop<=v[0:0];
                        8'h81: if(v==0 || v==1) auto_start<=v[0:0];
                        8'h82: if(v>=1 && v<=1000) begin
                            candidate_period<=v[15:0]; batch_loop<=0; batch_index<=0;
                            batch<=1; batch_failed<=0; state<=4;
                        end
                        8'h83: if(v>=1 && v<=1000) begin
                            candidate_period<=v[15:0]; batch_loop<=1; batch_index<=0;
                            batch<=1; batch_failed<=0; state<=4;
                        end
                        8'h84: if(v>=1 && v<=fall_adc && v>=outer_limit_adc) capture_adc<=v[11:0];
                        8'h85: if(v>=capture_adc && center_ext-value_ext>$signed({1'b0,rail_low}) && center_ext+value_ext<$signed({1'b0,rail_high})) fall_adc<=v[11:0];
                        8'h86: if(v>=1 && v<=100) kick_percent<=v[7:0];
                        8'h87: if(v>=1 && v<=1000) kick_ms<=v[15:0];
                        8'h88: if(v>=1 && v<=1000) judge_ms<=v[15:0];
                        8'h89: if(v>=1 && v<=60000) swing_timeout_ms<=v[15:0];
                        8'h8a: if(v>=1 && v<=1000) adc_timeout_ms<=v[15:0];
                        8'h8b: if(v>=0 && value_ext<center_ext-fall_ext) rail_low<=v[11:0];
                        8'h8c: if(value_ext>center_ext+fall_ext && v<=4092) rail_high<=v[11:0];
                        8'h8d: if(v>=1 && v<=capture_adc) outer_limit_adc<=v[15:0];
                        8'h8e: if(v>=1 && v<=100) inner_limit_percent<=v[7:0];
                        8'h8f: if(v>=0 && v<=100) inner_i_percent<=v[7:0];
                        8'h90: if(v>=0 && v<=10000) outer_i_adc<=v[15:0];
                        8'h91: if(v>=1 && v<=1000000 && goal_position<=v && goal_position>=-v) travel_counts<=v[31:0];
                        default: ;
                        endcase
                    end
                end
                4: begin
                    convert_micro<=gain_micro[(batch_loop?3:0)+batch_index];
                    setup_gain(batch_loop,batch_index,candidate_period); state<=1;
                end
                5: begin
                    if(!batch_failed) begin
                        if(batch_loop) begin
                            period_b_ms<=candidate_period;
                            kp_b<=batch_result[0]; ki_b<=batch_result[1]; kd_b<=batch_result[2]; epoch_b<=epoch_b+1'b1;
                        end else begin
                            period_a_ms<=candidate_period;
                            kp_a<=batch_result[0]; ki_a<=batch_result[1]; kd_a<=batch_result[2]; epoch_a<=epoch_a+1'b1;
                        end
                    end
                    batch<=0; state<=0;
                end
                default: state<=0;
            endcase
        end
    end
endmodule
