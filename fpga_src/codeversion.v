// Report code version
//
// Copyright (C) 2023  Kevin O'Connor <kevin@koconnor.net>
//
// This file may be distributed under the terms of the GNU GPLv3 license.

module codeversion (
    input clk,
    input wb_stb_i, input wb_cyc_i, input wb_we_i,
    input [7:0] wb_adr_i,
    input [7:0] wb_dat_i,
    output reg [7:0] wb_dat_o,
    output wb_ack_o
    );

    localparam MAJOR = 16'd0, MINOR = 8'd1, REV = 8'd10;

    wire [31:0] code_version = { MAJOR, MINOR, REV };

    // Command handling
    always @(*) begin
        case (wb_adr_i[1:0])
        default: wb_dat_o = code_version[7:0];
        1: wb_dat_o = code_version[15:8];
        2: wb_dat_o = code_version[23:16];
        3: wb_dat_o = code_version[31:24];
        endcase
    end
    assign wb_ack_o = 1;

endmodule
