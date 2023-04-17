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

    // Sum incoming samples
    reg [16:0] adc_sum_with_carry;
    wire reset_sum;
    reg [15:0] initial_sum;
    wire [16:0] initial_sum_with_carry = {initial_sum[15], initial_sum};
    always @(posedge clk) begin
        if (reset_sum)
            adc_sum_with_carry <= initial_sum_with_carry + adc_ch;
        else
            adc_sum_with_carry <= adc_sum_with_carry + adc_ch;
    end

    // Sum masking
    reg [15:0] sum_mask;
    wire [15:0] adc_sum = adc_sum_with_carry[15:0];
    wire [15:0] raw_sum_with_mask = adc_sum & sum_mask;
    wire did_underflow = adc_sum_with_carry[16] && initial_sum[15];
    wire did_overflow = adc_sum_with_carry > sum_mask;
    wire [15:0] masked_sum = (did_underflow ? 1'b0
                              : (did_overflow ? sum_mask : raw_sum_with_mask));

    // Sample shifting
    localparam SC_SHIFT8=0, SC_SHIFT10=1, SC_SHIFT13=2, SC_SHIFT5=3;
    wire [1:0] shift_type;
    wire [31:0] sample_shift8 = { sample[23:0], sample[31:24] };
    wire [31:0] sample_shift10 = { sample[21:0], sample[31:22] };
    wire [31:0] sample_shift13 = { sample[18:0], sample[31:19] };
    wire [31:0] sample_shift5 = { sample[26:0], sample[31:27] };
    wire [31:0] sample_shift = (shift_type==SC_SHIFT10 ? sample_shift10
                : (shift_type==SC_SHIFT13 ? sample_shift13
                : (shift_type==SC_SHIFT5 ? sample_shift5 : sample_shift8)));
    wire [15:0] sample_shift_masked = sample_shift[15:0] & ~sum_mask;
    wire [15:0] sample_merged_low = sample_shift_masked | masked_sum;
    wire [31:0] sample_merged = { sample_shift[31:16], sample_merged_low };

    // Collect data into a sample queue entry
    wire do_deposit;
    always @(posedge clk)
        if (do_deposit)
            sample <= sample_merged;
    wire [2:0] deposit_cnt_start;
    reg [2:0] deposit_cnt;
    always @(posedge clk) begin
        if (sq_active) begin
            if (do_deposit) begin
                if (deposit_cnt == 0)
                    deposit_cnt <= deposit_cnt_start;
                else
                    deposit_cnt <= deposit_cnt - 1'b1;
            end
        end else begin
            deposit_cnt <= 0;
        end
    end
    reg enable;
    always @(posedge clk)
        sample_avail <= enable && do_deposit && deposit_cnt == 0;

    // Configurable deposit types
    localparam DT_4x8=SC_SHIFT8, DT_3x10=SC_SHIFT10, DT_2x13=SC_SHIFT13,
               DT_6x5=SC_SHIFT5, DT_5x6=SC_SHIFT13 | 4;
    reg [2:0] deposit_type;
    assign shift_type = deposit_type[1:0];
    assign deposit_cnt_start = (deposit_type == DT_3x10 ? 3'd2
                               : (deposit_type == DT_2x13 ? 3'd1
                               : (deposit_type == DT_6x5 ? 3'd5
                               : (deposit_type == DT_5x6 ? 3'd4 : 3'd3))));

    // Track number of measurements to accumulate before depositing into sample
    reg [7:0] acc_cnt, cur_acc_cnt;
    assign do_deposit = cur_acc_cnt == 0;
    always @(posedge clk) begin
        if (sq_active) begin
            if (do_deposit)
                cur_acc_cnt <= acc_cnt;
            else
                cur_acc_cnt <= cur_acc_cnt - 1'b1;
        end else begin
            cur_acc_cnt <= 0;
        end
    end
    reg do_adc_add;
    assign reset_sum = !do_adc_add || do_deposit || !sq_active;

    // Command registers
    wire is_command_set_status;
    always @(posedge clk)
        if (is_command_set_status && !sq_active) begin
            enable <= wb_dat_i[0];
            do_adc_add <= wb_dat_i[1];
            deposit_type <= wb_dat_i[6:4];
        end
    wire is_command_set_acc_count;
    always @(posedge clk)
        if (is_command_set_acc_count && !sq_active)
            acc_cnt <= wb_dat_i;
    wire is_command_set_sum_mask;
    always @(posedge clk)
        if (is_command_set_sum_mask && !sq_active) begin
            if (!wb_adr_i[0])
                sum_mask[7:0] <= wb_dat_i;
            else
                sum_mask[15:8] <= wb_dat_i;
        end
    wire is_command_set_initial_sum;
    always @(posedge clk)
        if (is_command_set_initial_sum && !sq_active) begin
            if (!wb_adr_i[0])
                initial_sum[7:0] <= wb_dat_i;
            else
                initial_sum[15:8] <= wb_dat_i;
        end

    // Command handling
    wire is_command = wb_cyc_i && wb_stb_i && wb_we_i;
    assign is_command_set_status = is_command && wb_adr_i[2:0] == 0;
    assign is_command_set_acc_count = is_command && wb_adr_i[2:0] == 1;
    assign is_command_set_sum_mask = is_command && wb_adr_i[2:1] == 1;
    assign is_command_set_initial_sum = is_command && wb_adr_i[2:1] == 2;
    always @(*) begin
        case (wb_adr_i[2:0])
        default: wb_dat_o = { deposit_type, 2'b0, do_adc_add, enable };
        1: wb_dat_o = acc_cnt;
        2: wb_dat_o = sum_mask[7:0];
        3: wb_dat_o = sum_mask[15:8];
        4: wb_dat_o = initial_sum[7:0];
        5: wb_dat_o = initial_sum[15:8];
        endcase
    end
    assign wb_ack_o = 1;

endmodule
