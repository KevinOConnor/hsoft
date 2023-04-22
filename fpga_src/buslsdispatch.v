// Wishbone bus low-speed device dispatch
//
// Copyright (C) 2023  Kevin O'Connor <kevin@koconnor.net>
//
// This file may be distributed under the terms of the GNU GPLv3 license.

module buslsdispatch (
    input clk, input slow_clk,

    // Requester wishbone module
    input wb_stb_i, input wb_cyc_i, input wb_we_i,
    input [15:0] wb_adr_i, input [7:0] wb_dat_i,
    output [7:0] wb_dat_o, output wb_ack_o,

    // Code version reporting module
    output reg vers_wb_stb_o, output vers_wb_cyc_o, output vers_wb_we_o,
    output [15:0] vers_wb_adr_o, output [7:0] vers_wb_dat_o,
    input [7:0] vers_wb_dat_i, input vers_wb_ack_i,

    // ADC SPI module
    output reg adcspi_wb_stb_o, output adcspi_wb_cyc_o, output adcspi_wb_we_o,
    output [15:0] adcspi_wb_adr_o, output [7:0] adcspi_wb_dat_o,
    input [7:0] adcspi_wb_dat_i, input adcspi_wb_ack_i,

    // I2C module
    output reg i2c_wb_stb_o, output i2c_wb_cyc_o, output i2c_wb_we_o,
    output [15:0] i2c_wb_adr_o, output [7:0] i2c_wb_dat_o,
    input [7:0] i2c_wb_dat_i, input i2c_wb_ack_i
    );

    // Transfer wishbone messages across clock domains
    wire ls_stb_i, ls_cyc_i, ls_we_i;
    wire [15:0] ls_adr_i;
    wire [7:0] ls_dat_i;
    reg [7:0] ls_dat_o;
    reg ls_ack_o;
    wb_async_reg #(
        .DATA_WIDTH(8), .ADDR_WIDTH(16)
        ) cross_clock_domain(
        .wbm_clk(clk),
        .wbm_stb_i(wb_stb_i), .wbm_cyc_i(wb_cyc_i), .wbm_we_i(wb_we_i),
        .wbm_adr_i(wb_adr_i), .wbm_dat_i(wb_dat_i),
        .wbm_dat_o(wb_dat_o), .wbm_ack_o(wb_ack_o),

        .wbs_clk(slow_clk),
        .wbs_stb_o(ls_stb_i), .wbs_cyc_o(ls_cyc_i), .wbs_we_o(ls_we_i),
        .wbs_adr_o(ls_adr_i), .wbs_dat_o(ls_dat_i),
        .wbs_dat_i(ls_dat_o), .wbs_ack_i(ls_ack_o)
        );

    // Code version reporting module
    localparam VERS_ADDR = 8'h00;
    assign vers_wb_cyc_o=ls_cyc_i, vers_wb_we_o=ls_we_i;
    assign vers_wb_adr_o=ls_adr_i, vers_wb_dat_o=ls_dat_i;

    // ADC spi
    localparam ADCSPI_ADDR = 8'h01;
    assign adcspi_wb_cyc_o=ls_cyc_i, adcspi_wb_we_o=ls_we_i;
    assign adcspi_wb_adr_o=ls_adr_i, adcspi_wb_dat_o=ls_dat_i;

    // I2C module
    localparam I2C_ADDR = 8'h02;
    assign i2c_wb_cyc_o=ls_cyc_i, i2c_wb_we_o=ls_we_i;
    assign i2c_wb_adr_o=ls_adr_i, i2c_wb_dat_o=ls_dat_i;

    always @(*) begin
        vers_wb_stb_o = 0;
        adcspi_wb_stb_o = 0;
        i2c_wb_stb_o = 0;

        case (ls_adr_i[15:8])
        VERS_ADDR: begin
            vers_wb_stb_o = ls_stb_i;
            ls_dat_o = vers_wb_dat_i;
            ls_ack_o = vers_wb_ack_i;
        end
        ADCSPI_ADDR: begin
            adcspi_wb_stb_o = ls_stb_i;
            ls_dat_o = adcspi_wb_dat_i;
            ls_ack_o = adcspi_wb_ack_i;
        end
        I2C_ADDR: begin
            i2c_wb_stb_o = ls_stb_i;
            ls_dat_o = i2c_wb_dat_i;
            ls_ack_o = i2c_wb_ack_i;
        end
        default: begin
            ls_dat_o = 0;
            ls_ack_o = 1;
        end
        endcase
    end

endmodule
