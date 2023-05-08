// Storage for samples in a fifo
//
// Copyright (C) 2023  Kevin O'Connor <kevin@koconnor.net>
//
// This file may be distributed under the terms of the GNU GPLv3 license.

module sampfifo #(
    parameter QUEUE_SIZE = 128,
    parameter SAMPLE_W = 72,
    parameter ADDR_W = 13
    )(
    input clk,
    input [ADDR_W-1:0] raddr, output reg [SAMPLE_W-1:0] rdata, input ravail,
    input [ADDR_W-1:0] waddr, input [SAMPLE_W-1:0] wdata, input wavail
    );

    /* synthesis syn_ramstyle = no_rw_check */
    reg [SAMPLE_W-1:0] mem [QUEUE_SIZE-1:0];

    always @(posedge clk)
        if (ravail)
            rdata <= mem[raddr];

    always @(posedge clk)
        if (wavail)
            mem[waddr] <= wdata;

endmodule
