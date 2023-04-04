// Simple buffered output helper
//
// Copyright (C) 2023  Kevin O'Connor <kevin@koconnor.net>
//
// This file may be distributed under the terms of the GNU GPLv3 license.

module simpbuf(
    input clk,
    input [7:0] in_data, input in_avail, output in_pull,
    output [7:0] out_data, output out_avail, input out_pull
    );

    reg [7:0] buf_data;
    reg buf_filled;
    assign in_pull = !buf_filled || out_pull;
    always @(posedge clk) begin
        if (in_avail && in_pull) begin
            buf_data <= in_data;
            buf_filled <= 1;
        end else if (out_pull) begin
            buf_filled <= 0;
        end
    end
    assign out_avail = buf_filled;
    assign out_data = buf_data;

endmodule
