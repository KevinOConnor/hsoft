// Wishbone bus dispatch
//
// Copyright (C) 2023  Kevin O'Connor <kevin@koconnor.net>
//
// This file may be distributed under the terms of the GNU GPLv3 license.

module busdispatch (
    input clk,

    // Requester wishbone module
    input wb_stb_i, input wb_cyc_i, input wb_we_i,
    input [15:0] wb_adr_i, input [7:0] wb_dat_i,
    output reg [7:0] wb_dat_o, output reg wb_ack_o,

    // ADC channels
    output reg ch0_wb_stb_o, output ch0_wb_cyc_o, output ch0_wb_we_o,
    output [15:0] ch0_wb_adr_o, output [7:0] ch0_wb_dat_o,
    input [7:0] ch0_wb_dat_i, input ch0_wb_ack_i,

    output reg ch1_wb_stb_o, output ch1_wb_cyc_o, output ch1_wb_we_o,
    output [15:0] ch1_wb_adr_o, output [7:0] ch1_wb_dat_o,
    input [7:0] ch1_wb_dat_i, input ch1_wb_ack_i,

    output reg ch2_wb_stb_o, output ch2_wb_cyc_o, output ch2_wb_we_o,
    output [15:0] ch2_wb_adr_o, output [7:0] ch2_wb_dat_o,
    input [7:0] ch2_wb_dat_i, input ch2_wb_ack_i,

    output reg ch3_wb_stb_o, output ch3_wb_cyc_o, output ch3_wb_we_o,
    output [15:0] ch3_wb_adr_o, output [7:0] ch3_wb_dat_o,
    input [7:0] ch3_wb_dat_i, input ch3_wb_ack_i,

    // Sample queue reading
    output reg sq_wb_stb_o, output sq_wb_cyc_o, output sq_wb_we_o,
    output [15:0] sq_wb_adr_o, output [7:0] sq_wb_dat_o,
    input [7:0] sq_wb_dat_i, input sq_wb_ack_i,

    // ADC SPI module
    output reg adcspi_wb_stb_o, output adcspi_wb_cyc_o, output adcspi_wb_we_o,
    output [15:0] adcspi_wb_adr_o, output [7:0] adcspi_wb_dat_o,
    input [7:0] adcspi_wb_dat_i, input adcspi_wb_ack_i,

    // I2C module
    output reg i2c_wb_stb_o, output i2c_wb_cyc_o, output i2c_wb_we_o,
    output [15:0] i2c_wb_adr_o, output [7:0] i2c_wb_dat_o,
    input [7:0] i2c_wb_dat_i, input i2c_wb_ack_i
);

    // ADC channels
    localparam CH0_ADDR = "0";
    assign ch0_wb_cyc_o=wb_cyc_i, ch0_wb_we_o=wb_we_i;
    assign ch0_wb_adr_o=wb_adr_i, ch0_wb_dat_o=wb_dat_i;
    localparam CH1_ADDR = "1";
    assign ch1_wb_cyc_o=wb_cyc_i, ch1_wb_we_o=wb_we_i;
    assign ch1_wb_adr_o=wb_adr_i, ch1_wb_dat_o=wb_dat_i;
    localparam CH2_ADDR = "2";
    assign ch2_wb_cyc_o=wb_cyc_i, ch2_wb_we_o=wb_we_i;
    assign ch2_wb_adr_o=wb_adr_i, ch2_wb_dat_o=wb_dat_i;
    localparam CH3_ADDR = "3";
    assign ch3_wb_cyc_o=wb_cyc_i, ch3_wb_we_o=wb_we_i;
    assign ch3_wb_adr_o=wb_adr_i, ch3_wb_dat_o=wb_dat_i;

    // Sample queue
    localparam SQ_ADDR = "Q";
    assign sq_wb_cyc_o=wb_cyc_i, sq_wb_we_o=wb_we_i;
    assign sq_wb_adr_o=wb_adr_i, sq_wb_dat_o=wb_dat_i;

    // ADC spi
    localparam ADCSPI_ADDR = "S";
    assign adcspi_wb_cyc_o=wb_cyc_i, adcspi_wb_we_o=wb_we_i;
    assign adcspi_wb_adr_o=wb_adr_i, adcspi_wb_dat_o=wb_dat_i;

    // I2C module
    localparam I2C_ADDR = "I";
    assign i2c_wb_cyc_o=wb_cyc_i, i2c_wb_we_o=wb_we_i;
    assign i2c_wb_adr_o=wb_adr_i, i2c_wb_dat_o=wb_dat_i;

    always @(*) begin
        ch0_wb_stb_o = 0;
        ch1_wb_stb_o = 0;
        ch2_wb_stb_o = 0;
        ch3_wb_stb_o = 0;
        sq_wb_stb_o = 0;
        adcspi_wb_stb_o = 0;
        i2c_wb_stb_o = 0;

        case (wb_adr_i[15:8])
        CH0_ADDR: begin
            ch0_wb_stb_o = wb_stb_i;
            wb_dat_o = ch0_wb_dat_i;
            wb_ack_o = ch0_wb_ack_i;
        end
        CH1_ADDR: begin
            ch1_wb_stb_o = wb_stb_i;
            wb_dat_o = ch1_wb_dat_i;
            wb_ack_o = ch1_wb_ack_i;
        end
        CH2_ADDR: begin
            ch2_wb_stb_o = wb_stb_i;
            wb_dat_o = ch2_wb_dat_i;
            wb_ack_o = ch2_wb_ack_i;
        end
        CH3_ADDR: begin
            ch3_wb_stb_o = wb_stb_i;
            wb_dat_o = ch3_wb_dat_i;
            wb_ack_o = ch3_wb_ack_i;
        end
        SQ_ADDR: begin
            sq_wb_stb_o = wb_stb_i;
            wb_dat_o = sq_wb_dat_i;
            wb_ack_o = sq_wb_ack_i;
        end
        ADCSPI_ADDR: begin
            adcspi_wb_stb_o = wb_stb_i;
            wb_dat_o = adcspi_wb_dat_i;
            wb_ack_o = adcspi_wb_ack_i;
        end
        I2C_ADDR: begin
            i2c_wb_stb_o = wb_stb_i;
            wb_dat_o = i2c_wb_dat_i;
            wb_ack_o = i2c_wb_ack_i;
        end
        default: begin
            wb_dat_o = 0;
            wb_ack_o = 1;
        end
        endcase
    end

endmodule
