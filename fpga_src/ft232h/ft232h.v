// FT232H serial support across clock domains
//
// Copyright (C) 2023  Kevin O'Connor <kevin@koconnor.net>
//
// This file may be distributed under the terms of the GNU GPLv3 license.

module ft232h(
    input clk, input rst,

    input ft_clkout, output ft_oen,
    output ft_pwrsavn, output ft_siwun,
    input ft_rxfn, output ft_rdn, input [7:0] ft_data_in,
    input ft_txen, output ft_wrn, output [7:0] ft_data_out,
    output ft_data_out_enable,

    output [7:0] rx_data, output rx_avail,
    input [7:0] tx_data, input tx_avail, output tx_pull
    );

    // Asynchronous receive fifo
    wire rx_fifo_empty;
    assign rx_avail = !rx_fifo_empty;
    wire [7:0] ft_rx_data;
    wire ft_rx_avail, ft_rx_fifo_full;
    async_fifo #( .ASIZE(2) ) rx_fifo(
        .rclk(clk), .rrst_n(!rst), .rinc(1),
        .rdata(rx_data), .rempty(rx_fifo_empty),

        .wclk(ft_clkout), .wrst_n(!rst), .wfull(ft_rx_fifo_full),
        .winc(ft_rx_avail), .wdata(ft_rx_data)
        );

    // Asynchronous transmit fifo
    wire tx_fifo_full;
    assign tx_pull = !tx_fifo_full;
    wire [7:0] ft_tx_data;
    wire ft_tx_pull, ft_tx_fifo_empty;
    async_fifo #( .ASIZE(3) ) tx_fifo(
        .wclk(clk), .wrst_n(!rst),
        .winc(tx_avail), .wdata(tx_data), .wfull(tx_fifo_full),

        .rclk(ft_clkout), .rrst_n(!rst), .rinc(ft_tx_pull),
        .rdata(ft_tx_data), .rempty(ft_tx_fifo_empty)
        );

    // Simple buffer on transmit to avoid Quartus compiler warnings
    wire [7:0] buf_tx_data;
    wire buf_tx_avail, buf_tx_pull;
    simpbuf simple_buffer(
        .clk(ft_clkout),
        .in_data(ft_tx_data),
        .in_avail(!ft_tx_fifo_empty), .in_pull(ft_tx_pull),
        .out_data(buf_tx_data),
        .out_avail(buf_tx_avail), .out_pull(buf_tx_pull)
        );

    // FT245 protocol handling in ft_clk domain
    sync245 ft245_proto(
        .ft_clkout(ft_clkout), .ft_oen(ft_oen),
        .ft_rxfn(ft_rxfn), .ft_rdn(ft_rdn),
        .ft_data_in(ft_data_in),
        .ft_txen(ft_txen), .ft_wrn(ft_wrn),
        .ft_siwun(ft_siwun), .ft_pwrsavn(ft_pwrsavn),
        .ft_data_out(ft_data_out),
        .ft_data_out_enable(ft_data_out_enable),

        .rx_data(ft_rx_data),
        .rx_avail(ft_rx_avail), .rx_pull(!ft_rx_fifo_full),
        .tx_data(buf_tx_data),
        .tx_avail(buf_tx_avail), .tx_pull(buf_tx_pull)
        );

endmodule
