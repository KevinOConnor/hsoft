// Trigger on an adc value
//
// Copyright (C) 2023  Kevin O'Connor <kevin@koconnor.net>
//
// This file may be distributed under the terms of the GNU GPLv3 license.

module adctrigger (
    input clk,
    input sq_active, output reg sq_trigger,
    input [7:0] adc,

    input wb_stb_i, input wb_cyc_i, input wb_we_i,
    input [15:0] wb_adr_i,
    input [7:0] wb_dat_i,
    output reg [7:0] wb_dat_o,
    output wb_ack_o
    );

    // Trigger detection
    reg [7:0] thresh;
    wire is_greater = thresh > adc;
    reg found_inverse;
    reg enable, require_inverse, cmp_greater;
    always @(posedge clk) begin
        sq_trigger = 0;
        if (enable) begin
            if (is_greater == cmp_greater) begin
                if (!require_inverse || found_inverse) begin
                    sq_trigger = 1;
                    found_inverse <= 0;
                end
            end else begin
                found_inverse <= 1;
            end
        end else begin
            found_inverse <= 0;
        end
    end

    // Command registers
    wire is_command_set_status;
    always @(posedge clk) begin
        if (is_command_set_status) begin
            enable <= wb_dat_i[0];
            if (!enable || !wb_dat_i[0]) begin
                cmp_greater <= wb_dat_i[1];
                require_inverse <= wb_dat_i[2];
            end
        end
    end
    wire is_command_set_thresh;
    always @(posedge clk)
        if (is_command_set_thresh && !enable)
            thresh <= wb_dat_i;

    // Command handling
    wire is_command = wb_cyc_i && wb_stb_i && wb_we_i;
    assign is_command_set_status = is_command && wb_adr_i[1:0] == 0;
    assign is_command_set_thresh = is_command && wb_adr_i[1:0] == 1;
    always @(*) begin
        case (wb_adr_i[1:0])
        default: wb_dat_o = { require_inverse, cmp_greater, enable };
        1: wb_dat_o = thresh;
        endcase
    end
    assign wb_ack_o = 1;

endmodule
