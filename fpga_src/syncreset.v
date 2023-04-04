// Synchronous reset generation
//
// Copyright (C) 2023  Kevin O'Connor <kevin@koconnor.net>
//
// This file may be distributed under the terms of the GNU GPLv3 license.

module syncreset (
    input clk,
    output rst
    );

    reg [2:0] cnt = 0;
    always @(posedge clk)
        cnt <= cnt + 1'b1;

    reg need_reset = 1;
    always @(posedge clk)
        if (cnt == 7)
            need_reset <= 0;

    assign rst = need_reset;

endmodule
