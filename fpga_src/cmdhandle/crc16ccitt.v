// Calculate crc16-ccitt
//
// Copyright (C) 2023  Kevin O'Connor <kevin@koconnor.net>
//
// This file may be distributed under the terms of the GNU GPLv3 license.

module crc16ccitt (
    input clk,
    input clear,
    input [7:0] data, input avail,
    output reg [15:0] crc
    );

    wire [7:0] xd1 = data ^ crc[7:0];
    wire [7:0] xd2 = {xd1[7:4] ^ xd1[3:0], xd1[3:0]};
    wire [15:0] c1 = {xd2, crc[15:12], crc[11:8] ^ xd2[7:4]};
    wire [15:0] c2 = {c1[15:11], c1[10:3] ^ xd2, c1[2:0]};
    always @(posedge clk) begin
        if (clear) begin
            crc <= 16'hffff;
        end else if (avail) begin
            crc <= c2;
        end
    end

endmodule
