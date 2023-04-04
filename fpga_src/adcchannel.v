// Handling of each adc channel
//
// Copyright (C) 2023  Kevin O'Connor <kevin@koconnor.net>
//
// This file may be distributed under the terms of the GNU GPLv3 license.

module adcchannel (
    input clk,

    input adc_clk, input [7:0] adc_ch,

    input sq_active, output sq_trigger,
    output [31:0] sample, output sample_avail,

    input wb_stb_i, input wb_cyc_i, input wb_we_i,
    input [15:0] wb_adr_i,
    input [7:0] wb_dat_i,
    output [7:0] wb_dat_o,
    output wb_ack_o
    );

    // Obtain data from pins
    wire [7:0] extadc_ch;
    maxadcsync extadc_sync_ch(
        .main_clk(clk), .raw_adc(extadc_ch),
        .adc_clk(adc_clk), .adc_ch(adc_ch)
        );

    // Collect ADC measurements into sample entries
    wire is_samp_wb = wb_adr_i[5];
    wire [7:0] samp_wb_dat_o;
    wire samp_wb_ack_o;
    sampadcacc extadc_sample_ch(
        .clk(clk), .adc_ch(extadc_ch), .sq_active(sq_active),
        .sample(sample), .sample_avail(sample_avail),

        .wb_stb_i(wb_stb_i && is_samp_wb), .wb_cyc_i(wb_cyc_i),
        .wb_we_i(wb_we_i),
        .wb_adr_i(wb_adr_i), .wb_dat_i(wb_dat_i),
        .wb_dat_o(samp_wb_dat_o), .wb_ack_o(samp_wb_ack_o)
        );

    // Triggers
    wire [7:0] trig_wb_dat_o;
    wire trig_wb_ack_o;
    adctrigger trigger_handler(
        .clk(clk),
        .sq_active(sq_active),
        .sq_trigger(sq_trigger),
        .adc(extadc_ch),

        .wb_stb_i(wb_stb_i && !is_samp_wb), .wb_cyc_i(wb_cyc_i),
        .wb_we_i(wb_we_i),
        .wb_adr_i(wb_adr_i), .wb_dat_i(wb_dat_i),
        .wb_dat_o(trig_wb_dat_o), .wb_ack_o(trig_wb_ack_o)
        );

    // Command muxing
    assign wb_dat_o = is_samp_wb ? samp_wb_dat_o : trig_wb_dat_o;
    assign wb_ack_o = is_samp_wb ? samp_wb_ack_o : trig_wb_ack_o;

endmodule
