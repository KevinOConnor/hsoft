// Collect multiple ADC reading into a sample queue entry
//
// Copyright (C) 2023  Kevin O'Connor <kevin@koconnor.net>
//
// This file may be distributed under the terms of the GNU GPLv3 license.

module sampadcacc (
    input clk,
    input [7:0] adc_ch, input sq_active,

    output reg [31:0] sample, output reg sample_avail,

    input wb_stb_i, input wb_cyc_i, input wb_we_i,
    input [15:0] wb_adr_i,
    input [7:0] wb_dat_i,
    output reg [7:0] wb_dat_o,
    output wb_ack_o
    );

    // Track when to read data
    reg [7:0] read_cnt, cur_read_cnt;
    wire do_read = cur_read_cnt == 0;
    always @(posedge clk) begin
        if (sq_active) begin
            if (do_read)
                cur_read_cnt <= read_cnt;
            else
                cur_read_cnt <= cur_read_cnt - 1'b1;
        end else begin
            cur_read_cnt <= 0;
        end
    end

    // Collect data into a sample queue entry
    always @(posedge clk)
        if (do_read)
            sample <= { adc_ch, sample[31:8] };
    reg [1:0] sq_cnt;
    always @(posedge clk) begin
        if (sq_active) begin
            if (do_read)
                sq_cnt <= sq_cnt + 1'b1;
        end else begin
            sq_cnt <= 0;
        end
    end
    reg enable;
    always @(posedge clk)
        sample_avail <= enable && do_read && sq_cnt == 0;

    // Command registers
    wire is_command_set_status;
    always @(posedge clk)
        if (is_command_set_status && !sq_active)
            enable <= wb_dat_i[0];
    wire is_command_set_read_count;
    always @(posedge clk)
        if (is_command_set_read_count && !sq_active)
            read_cnt <= wb_dat_i;

    // Command handling
    wire is_command = wb_cyc_i && wb_stb_i && wb_we_i;
    assign is_command_set_status = is_command && wb_adr_i[1:0] == 0;
    assign is_command_set_read_count = is_command && wb_adr_i[1:0] == 1;
    always @(*) begin
        case (wb_adr_i[1:0])
        default: wb_dat_o = { enable };
        1: wb_dat_o = read_cnt;
        endcase
    end
    assign wb_ack_o = 1;

endmodule
