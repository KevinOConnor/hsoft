// Select sample to add to samples queue
//
// Copyright (C) 2023  Kevin O'Connor <kevin@koconnor.net>
//
// This file may be distributed under the terms of the GNU GPLv3 license.

module trigselect #(
    parameter NUM_SOURCES = 1
    )(
    input clk,
    input [NUM_SOURCES-1:0] triggers,
    output sq_trigger
    );

    assign sq_trigger = !(!triggers);

endmodule
