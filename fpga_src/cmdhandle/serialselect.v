// Select between two upstream serial ports
//
// Copyright (C) 2023  Kevin O'Connor <kevin@koconnor.net>
//
// This file may be distributed under the terms of the GNU GPLv3 license.

module serialselect (
    input clk,

    input uart_stb_i, input [5:0] uart_seq_i, input uart_we_i,
    input [15:0] uart_adr_i, input [7:0] uart_dat_i,
    output uart_tx_avail, output [7:0] uart_tx_data, input uart_tx_pull,

    input usbhi_stb_i, input [5:0] usbhi_seq_i, input usbhi_we_i,
    input [15:0] usbhi_adr_i, input [7:0] usbhi_dat_i,
    output usbhi_tx_avail, output [7:0] usbhi_tx_data, input usbhi_tx_pull,

    output stb_o, output [5:0] seq_o, output we_o,
    output [15:0] adr_o, output [7:0] dat_o,
    input tx_avail, input [7:0] tx_data, output tx_pull
    );

    // Route new incoming commands
    assign stb_o = uart_stb_i || usbhi_stb_i;
    assign seq_o = usbhi_stb_i ? usbhi_seq_i : uart_seq_i;
    assign we_o = usbhi_stb_i ? usbhi_we_i : uart_we_i;
    assign adr_o = usbhi_stb_i ? usbhi_adr_i : uart_adr_i;
    assign dat_o = usbhi_stb_i ? usbhi_dat_i : uart_dat_i;

    // Route responses
    reg usbhi_enabled;
    always @(posedge clk)
        if (stb_o)
            usbhi_enabled <= usbhi_stb_i;
    assign tx_pull = usbhi_enabled ? usbhi_tx_pull : uart_tx_pull;
    assign uart_tx_avail = usbhi_enabled ? 1'b0 : tx_avail;
    assign usbhi_tx_avail = usbhi_enabled ? tx_avail : 1'b0;
    assign uart_tx_data = tx_data;
    assign usbhi_tx_data = tx_data;

endmodule
