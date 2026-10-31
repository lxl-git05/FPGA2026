module gw_gao(
    \a_set_ticks[31] ,
    \a_set_ticks[30] ,
    \a_set_ticks[29] ,
    \a_set_ticks[28] ,
    \a_set_ticks[27] ,
    \a_set_ticks[26] ,
    \a_set_ticks[25] ,
    \a_set_ticks[24] ,
    \a_set_ticks[23] ,
    \a_set_ticks[22] ,
    \a_set_ticks[21] ,
    \a_set_ticks[20] ,
    \a_set_ticks[19] ,
    \a_set_ticks[18] ,
    \a_set_ticks[17] ,
    \a_set_ticks[16] ,
    \a_set_ticks[15] ,
    \a_set_ticks[14] ,
    \a_set_ticks[13] ,
    \a_set_ticks[12] ,
    \a_set_ticks[11] ,
    \a_set_ticks[10] ,
    \a_set_ticks[9] ,
    \a_set_ticks[8] ,
    \a_set_ticks[7] ,
    \a_set_ticks[6] ,
    \a_set_ticks[5] ,
    \a_set_ticks[4] ,
    \a_set_ticks[3] ,
    \a_set_ticks[2] ,
    \a_set_ticks[1] ,
    \a_set_ticks[0] ,
    \a_real[31] ,
    \a_real[30] ,
    \a_real[29] ,
    \a_real[28] ,
    \a_real[27] ,
    \a_real[26] ,
    \a_real[25] ,
    \a_real[24] ,
    \a_real[23] ,
    \a_real[22] ,
    \a_real[21] ,
    \a_real[20] ,
    \a_real[19] ,
    \a_real[18] ,
    \a_real[17] ,
    \a_real[16] ,
    \a_real[15] ,
    \a_real[14] ,
    \a_real[13] ,
    \a_real[12] ,
    \a_real[11] ,
    \a_real[10] ,
    \a_real[9] ,
    \a_real[8] ,
    \a_real[7] ,
    \a_real[6] ,
    \a_real[5] ,
    \a_real[4] ,
    \a_real[3] ,
    \a_real[2] ,
    \a_real[1] ,
    \a_real[0] ,
    clk,
    tms_pad_i,
    tck_pad_i,
    tdi_pad_i,
    tdo_pad_o
);

input \a_set_ticks[31] ;
input \a_set_ticks[30] ;
input \a_set_ticks[29] ;
input \a_set_ticks[28] ;
input \a_set_ticks[27] ;
input \a_set_ticks[26] ;
input \a_set_ticks[25] ;
input \a_set_ticks[24] ;
input \a_set_ticks[23] ;
input \a_set_ticks[22] ;
input \a_set_ticks[21] ;
input \a_set_ticks[20] ;
input \a_set_ticks[19] ;
input \a_set_ticks[18] ;
input \a_set_ticks[17] ;
input \a_set_ticks[16] ;
input \a_set_ticks[15] ;
input \a_set_ticks[14] ;
input \a_set_ticks[13] ;
input \a_set_ticks[12] ;
input \a_set_ticks[11] ;
input \a_set_ticks[10] ;
input \a_set_ticks[9] ;
input \a_set_ticks[8] ;
input \a_set_ticks[7] ;
input \a_set_ticks[6] ;
input \a_set_ticks[5] ;
input \a_set_ticks[4] ;
input \a_set_ticks[3] ;
input \a_set_ticks[2] ;
input \a_set_ticks[1] ;
input \a_set_ticks[0] ;
input \a_real[31] ;
input \a_real[30] ;
input \a_real[29] ;
input \a_real[28] ;
input \a_real[27] ;
input \a_real[26] ;
input \a_real[25] ;
input \a_real[24] ;
input \a_real[23] ;
input \a_real[22] ;
input \a_real[21] ;
input \a_real[20] ;
input \a_real[19] ;
input \a_real[18] ;
input \a_real[17] ;
input \a_real[16] ;
input \a_real[15] ;
input \a_real[14] ;
input \a_real[13] ;
input \a_real[12] ;
input \a_real[11] ;
input \a_real[10] ;
input \a_real[9] ;
input \a_real[8] ;
input \a_real[7] ;
input \a_real[6] ;
input \a_real[5] ;
input \a_real[4] ;
input \a_real[3] ;
input \a_real[2] ;
input \a_real[1] ;
input \a_real[0] ;
input clk;
input tms_pad_i;
input tck_pad_i;
input tdi_pad_i;
output tdo_pad_o;

wire \a_set_ticks[31] ;
wire \a_set_ticks[30] ;
wire \a_set_ticks[29] ;
wire \a_set_ticks[28] ;
wire \a_set_ticks[27] ;
wire \a_set_ticks[26] ;
wire \a_set_ticks[25] ;
wire \a_set_ticks[24] ;
wire \a_set_ticks[23] ;
wire \a_set_ticks[22] ;
wire \a_set_ticks[21] ;
wire \a_set_ticks[20] ;
wire \a_set_ticks[19] ;
wire \a_set_ticks[18] ;
wire \a_set_ticks[17] ;
wire \a_set_ticks[16] ;
wire \a_set_ticks[15] ;
wire \a_set_ticks[14] ;
wire \a_set_ticks[13] ;
wire \a_set_ticks[12] ;
wire \a_set_ticks[11] ;
wire \a_set_ticks[10] ;
wire \a_set_ticks[9] ;
wire \a_set_ticks[8] ;
wire \a_set_ticks[7] ;
wire \a_set_ticks[6] ;
wire \a_set_ticks[5] ;
wire \a_set_ticks[4] ;
wire \a_set_ticks[3] ;
wire \a_set_ticks[2] ;
wire \a_set_ticks[1] ;
wire \a_set_ticks[0] ;
wire \a_real[31] ;
wire \a_real[30] ;
wire \a_real[29] ;
wire \a_real[28] ;
wire \a_real[27] ;
wire \a_real[26] ;
wire \a_real[25] ;
wire \a_real[24] ;
wire \a_real[23] ;
wire \a_real[22] ;
wire \a_real[21] ;
wire \a_real[20] ;
wire \a_real[19] ;
wire \a_real[18] ;
wire \a_real[17] ;
wire \a_real[16] ;
wire \a_real[15] ;
wire \a_real[14] ;
wire \a_real[13] ;
wire \a_real[12] ;
wire \a_real[11] ;
wire \a_real[10] ;
wire \a_real[9] ;
wire \a_real[8] ;
wire \a_real[7] ;
wire \a_real[6] ;
wire \a_real[5] ;
wire \a_real[4] ;
wire \a_real[3] ;
wire \a_real[2] ;
wire \a_real[1] ;
wire \a_real[0] ;
wire clk;
wire tms_pad_i;
wire tck_pad_i;
wire tdi_pad_i;
wire tdo_pad_o;
wire tms_i_c;
wire tck_i_c;
wire tdi_i_c;
wire tdo_o_c;
wire [9:0] control0;
wire gao_jtag_tck;
wire gao_jtag_reset;
wire run_test_idle_er1;
wire run_test_idle_er2;
wire shift_dr_capture_dr;
wire update_dr;
wire pause_dr;
wire enable_er1;
wire enable_er2;
wire gao_jtag_tdi;
wire tdo_er1;

IBUF tms_ibuf (
    .I(tms_pad_i),
    .O(tms_i_c)
);

IBUF tck_ibuf (
    .I(tck_pad_i),
    .O(tck_i_c)
);

IBUF tdi_ibuf (
    .I(tdi_pad_i),
    .O(tdi_i_c)
);

OBUF tdo_obuf (
    .I(tdo_o_c),
    .O(tdo_pad_o)
);

GW_JTAG  u_gw_jtag(
    .tms_pad_i(tms_i_c),
    .tck_pad_i(tck_i_c),
    .tdi_pad_i(tdi_i_c),
    .tdo_pad_o(tdo_o_c),
    .tck_o(gao_jtag_tck),
    .test_logic_reset_o(gao_jtag_reset),
    .run_test_idle_er1_o(run_test_idle_er1),
    .run_test_idle_er2_o(run_test_idle_er2),
    .shift_dr_capture_dr_o(shift_dr_capture_dr),
    .update_dr_o(update_dr),
    .pause_dr_o(pause_dr),
    .enable_er1_o(enable_er1),
    .enable_er2_o(enable_er2),
    .tdi_o(gao_jtag_tdi),
    .tdo_er1_i(tdo_er1),
    .tdo_er2_i(1'b0)
);

gw_con_top  u_icon_top(
    .tck_i(gao_jtag_tck),
    .tdi_i(gao_jtag_tdi),
    .tdo_o(tdo_er1),
    .rst_i(gao_jtag_reset),
    .control0(control0[9:0]),
    .enable_i(enable_er1),
    .shift_dr_capture_dr_i(shift_dr_capture_dr),
    .update_dr_i(update_dr)
);

ao_top_0  u_la0_top(
    .control(control0[9:0]),
    .trig0_i({\a_set_ticks[31] ,\a_set_ticks[30] ,\a_set_ticks[29] ,\a_set_ticks[28] ,\a_set_ticks[27] ,\a_set_ticks[26] ,\a_set_ticks[25] ,\a_set_ticks[24] ,\a_set_ticks[23] ,\a_set_ticks[22] ,\a_set_ticks[21] ,\a_set_ticks[20] ,\a_set_ticks[19] ,\a_set_ticks[18] ,\a_set_ticks[17] ,\a_set_ticks[16] ,\a_set_ticks[15] ,\a_set_ticks[14] ,\a_set_ticks[13] ,\a_set_ticks[12] ,\a_set_ticks[11] ,\a_set_ticks[10] ,\a_set_ticks[9] ,\a_set_ticks[8] ,\a_set_ticks[7] ,\a_set_ticks[6] ,\a_set_ticks[5] ,\a_set_ticks[4] ,\a_set_ticks[3] ,\a_set_ticks[2] ,\a_set_ticks[1] ,\a_set_ticks[0] ,\a_real[31] ,\a_real[30] ,\a_real[29] ,\a_real[28] ,\a_real[27] ,\a_real[26] ,\a_real[25] ,\a_real[24] ,\a_real[23] ,\a_real[22] ,\a_real[21] ,\a_real[20] ,\a_real[19] ,\a_real[18] ,\a_real[17] ,\a_real[16] ,\a_real[15] ,\a_real[14] ,\a_real[13] ,\a_real[12] ,\a_real[11] ,\a_real[10] ,\a_real[9] ,\a_real[8] ,\a_real[7] ,\a_real[6] ,\a_real[5] ,\a_real[4] ,\a_real[3] ,\a_real[2] ,\a_real[1] ,\a_real[0] }),
    .data_i({\a_set_ticks[31] ,\a_set_ticks[30] ,\a_set_ticks[29] ,\a_set_ticks[28] ,\a_set_ticks[27] ,\a_set_ticks[26] ,\a_set_ticks[25] ,\a_set_ticks[24] ,\a_set_ticks[23] ,\a_set_ticks[22] ,\a_set_ticks[21] ,\a_set_ticks[20] ,\a_set_ticks[19] ,\a_set_ticks[18] ,\a_set_ticks[17] ,\a_set_ticks[16] ,\a_set_ticks[15] ,\a_set_ticks[14] ,\a_set_ticks[13] ,\a_set_ticks[12] ,\a_set_ticks[11] ,\a_set_ticks[10] ,\a_set_ticks[9] ,\a_set_ticks[8] ,\a_set_ticks[7] ,\a_set_ticks[6] ,\a_set_ticks[5] ,\a_set_ticks[4] ,\a_set_ticks[3] ,\a_set_ticks[2] ,\a_set_ticks[1] ,\a_set_ticks[0] ,\a_real[31] ,\a_real[30] ,\a_real[29] ,\a_real[28] ,\a_real[27] ,\a_real[26] ,\a_real[25] ,\a_real[24] ,\a_real[23] ,\a_real[22] ,\a_real[21] ,\a_real[20] ,\a_real[19] ,\a_real[18] ,\a_real[17] ,\a_real[16] ,\a_real[15] ,\a_real[14] ,\a_real[13] ,\a_real[12] ,\a_real[11] ,\a_real[10] ,\a_real[9] ,\a_real[8] ,\a_real[7] ,\a_real[6] ,\a_real[5] ,\a_real[4] ,\a_real[3] ,\a_real[2] ,\a_real[1] ,\a_real[0] }),
    .clk_i(clk)
);

endmodule
