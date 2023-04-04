// MAX19506 adc input clock synchronization
//
// Copyright (C) 2023  Kevin O'Connor <kevin@koconnor.net>
//
// This file may be distributed under the terms of the GNU GPLv3 license.

module maxadcsync(
    input main_clk,
    input adc_clk,

    input [7:0] adc_ch,
    output [7:0] raw_adc
    );

    // Read from input pins
    reg [7:0] adc_buf;
    always @(posedge adc_clk)
        adc_buf <= adc_ch;

    // Store in register using main clock
    reg [7:0] main_buf;
    always @(posedge main_clk)
        main_buf <= adc_buf;

    assign raw_adc = main_buf;

endmodule
