// Module for reading commands from serial port
//
// Copyright (C) 2023  Kevin O'Connor <kevin@koconnor.net>
//
// This file may be distributed under the terms of the GNU GPLv3 license.

module serialcmd (
    input clk,

    input [7:0] uart_rx_data, input uart_rx_avail,
    output [7:0] uart_tx_data, output uart_tx_avail, input uart_tx_pull,

    input [7:0] usbhi_rx_data, input usbhi_rx_avail,
    output [7:0] usbhi_tx_data, output usbhi_tx_avail, input usbhi_tx_pull,

    input [31:0] samp_stream_data, input [7:0] samp_stream_count,
    input samp_stream_avail, output samp_stream_pull,

    output wb_stb_o, output wb_cyc_o, output wb_we_o,
    output [15:0] wb_adr_o,
    output [7:0] wb_dat_o,
    input [7:0] wb_dat_i,
    input wb_ack_i
    );

    // Command parsing for uart and usbhi
    wire uart_stb, uart_we;
    wire [5:0] uart_seq;
    wire [15:0] uart_adr;
    wire [7:0] uart_dat;
    msgparse uart_serial(
        .clk(clk), .rx_data(uart_rx_data), .rx_avail(uart_rx_avail),
        .stb_o(uart_stb), .seq_o(uart_seq), .we_o(uart_we),
        .adr_o(uart_adr), .dat_o(uart_dat)
        );
    wire usbhi_stb, usbhi_we;
    wire [5:0] usbhi_seq;
    wire [15:0] usbhi_adr;
    wire [7:0] usbhi_dat;
    msgparse usbhi_serial(
        .clk(clk), .rx_data(usbhi_rx_data), .rx_avail(usbhi_rx_avail),
        .stb_o(usbhi_stb), .seq_o(usbhi_seq), .we_o(usbhi_we),
        .adr_o(usbhi_adr), .dat_o(usbhi_dat)
        );

    // Uart / usbhi input selection
    wire req_stb, req_we;
    wire [5:0] req_seq;
    wire [15:0] req_adr;
    wire [7:0] req_dat;
    wire [7:0] tx_data;
    wire tx_avail, tx_pull;
    serialselect serial_select(
        .clk(clk),

        .uart_stb_i(uart_stb), .uart_seq_i(uart_seq), .uart_we_i(uart_we),
        .uart_adr_i(uart_adr), .uart_dat_i(uart_dat),
        .uart_tx_data(uart_tx_data), .uart_tx_avail(uart_tx_avail),
        .uart_tx_pull(uart_tx_pull),

        .usbhi_stb_i(usbhi_stb), .usbhi_seq_i(usbhi_seq), .usbhi_we_i(usbhi_we),
        .usbhi_adr_i(usbhi_adr), .usbhi_dat_i(usbhi_dat),
        .usbhi_tx_data(usbhi_tx_data), .usbhi_tx_avail(usbhi_tx_avail),
        .usbhi_tx_pull(usbhi_tx_pull),

        .stb_o(req_stb), .seq_o(req_seq), .we_o(req_we),
        .adr_o(req_adr), .dat_o(req_dat),
        .tx_data(tx_data), .tx_avail(tx_avail), .tx_pull(tx_pull)
        );

    // Generate wishbone bus request for incoming commands
    wire [31:0] resp_data;
    wire [7:0] resp_count;
    wire resp_avail, resp_pull;
    wbcmd wishbone_command(
        .clk(clk),

        .req_stb_i(req_stb), .req_seq_i(req_seq), .req_we_i(req_we),
        .req_adr_i(req_adr), .req_dat_i(req_dat),

        .wb_stb_o(wb_stb_o), .wb_cyc_o(wb_cyc_o), .wb_we_o(wb_we_o),
        .wb_adr_o(wb_adr_o), .wb_dat_o(wb_dat_o),
        .wb_dat_i(wb_dat_i), .wb_ack_i(wb_ack_i),

        .resp_data(resp_data), .resp_count(resp_count),
        .resp_avail(resp_avail), .resp_pull(resp_pull)
        );

    // Tx content selection
    wire [31:0] strm_data;
    wire [7:0] strm_count;
    wire [3:0] strm_id;
    wire strm_avail, strm_pull;
    wire [3:0] send_id;
    streamselect stream_select(
        .clk(clk),

        .resp_data(resp_data), .resp_count(resp_count),
        .resp_avail(resp_avail), .resp_pull(resp_pull),

        .samp_stream_data(samp_stream_data),
        .samp_stream_count(samp_stream_count),
        .samp_stream_avail(samp_stream_avail),
        .samp_stream_pull(samp_stream_pull),

        .strm_data(strm_data), .strm_count(strm_count),
        .strm_id(strm_id), .strm_avail(strm_avail), .strm_pull(strm_pull),

        .send_id(send_id)
        );

    // Tx message encoding
    msgencode message_encoder(
        .clk(clk),

        .strm_data(strm_data), .strm_count(strm_count),
        .strm_id(strm_id), .strm_avail(strm_avail), .strm_pull(strm_pull),

        .send_id(send_id),

        .tx_data(tx_data), .tx_avail(tx_avail), .tx_pull(tx_pull)
        );

endmodule
