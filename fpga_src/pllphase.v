// Adjust the PLL phase for the adc clock line
//
// Copyright (C) 2023  Kevin O'Connor <kevin@koconnor.net>
//
// This file may be distributed under the terms of the GNU GPLv3 license.

module pllphase  #(
    parameter PLL_COUNTER = 3'd0
    )(
    input clk,

    output [2:0] phasecounterselect,
    output phasestep, output phaseupdown, output scanclk,
    input phasedone,

    input wb_stb_i, input wb_cyc_i, input wb_we_i,
    input [7:0] wb_adr_i,
    input [7:0] wb_dat_i,
    output reg [7:0] wb_dat_o,
    output wb_ack_o
    );

    // Phase adjusting
    localparam PS_IDLE = 2'd0, PS_SIG1 = 2'd1, PS_SIG2 = 2'd2, PS_SIG3 = 2'd3;
    reg [1:0] state = 0;
    reg [7:0] cur_phase = 0, req_phase = 0;
    wire have_diff = cur_phase != req_phase;
    always @(posedge clk)
        if (state != PS_IDLE || (have_diff && phasedone))
            state <= state + 1'd1;
    always @(posedge clk) begin
        if (state == PS_SIG1) begin
            if (phaseupdown)
                cur_phase <= cur_phase + 1'b1;
            else
                cur_phase <= cur_phase - 1'b1;
        end
    end

    // Assign signals
    assign phasecounterselect = PLL_COUNTER;
    assign scanclk = clk;
    assign phaseupdown = req_phase > cur_phase;
    assign phasestep = state != PS_IDLE;

    // Command registers
    wire is_command_set_phase;
    always @(posedge clk)
        if (is_command_set_phase && !have_diff)
            req_phase <= wb_dat_i;

    // Command handling
    wire is_command = wb_cyc_i && wb_stb_i && wb_we_i;
    assign is_command_set_phase = is_command && wb_adr_i[2:0] == 1;
    always @(*) begin
        case (wb_adr_i[2:0])
        default: wb_dat_o = { have_diff };
        1: wb_dat_o = req_phase;
        2: wb_dat_o = cur_phase;
        endcase
    end
    assign wb_ack_o = 1;

endmodule
