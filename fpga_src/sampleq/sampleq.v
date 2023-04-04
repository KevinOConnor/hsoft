// Queue for measurement samples
//
// Copyright (C) 2023  Kevin O'Connor <kevin@koconnor.net>
//
// This file may be distributed under the terms of the GNU GPLv3 license.

module sampleq(
    input clk,

    input [31:0] sample, input sample_avail, output reg active,
    input trigger,

    output [31:0] samp_stream_data, output reg [7:0] samp_stream_count,
    output reg samp_stream_avail, input samp_stream_pull,

    input wb_stb_i, input wb_cyc_i, input wb_we_i,
    input [15:0] wb_adr_i,
    input [7:0] wb_dat_i,
    output reg [7:0] wb_dat_o,
    output wb_ack_o
    );

    localparam ADDR_W = 13;

    // Memory storage for samples
    wire [ADDR_W-1:0] sfifo_raddr;
    wire [31:0] sfifo_rdata;
    wire sfifo_ravail;
    wire [ADDR_W-1:0] sfifo_waddr;
    wire [31:0] sfifo_wdata;
    wire sfifo_wavail;
    sampfifo #(
        .ADDR_W(ADDR_W)
        ) sample_fifo(
        .clk(clk),
        .raddr(sfifo_raddr), .rdata(sfifo_rdata), .ravail(sfifo_ravail),
        .waddr(sfifo_waddr), .wdata(sfifo_wdata), .wavail(sfifo_wavail)
        );

    // Add incoming sample to sample fifo
    assign sfifo_wdata = sample;
    assign sfifo_wavail = sample_avail && active;
    reg [31:0] fifo_push_counter;
    always @(posedge clk)
        if (sfifo_wavail)
            fifo_push_counter <= fifo_push_counter + 1'b1;
    wire [ADDR_W-1:0] fifo_push_ptr = fifo_push_counter[ADDR_W-1:0];
    assign sfifo_waddr = fifo_push_ptr;

    // Stream data out of fifo
    reg [ADDR_W-1:0] fifo_pull_ptr;
    wire [ADDR_W-1:0] fifo_diff = fifo_push_ptr - fifo_pull_ptr;
    wire [7:0] fifo_diff_cap = fifo_diff > 255 ? 8'd255 : fifo_diff[7:0];
    reg [31:0] frame_count;
    always @(posedge clk)
        samp_stream_count <= (fifo_diff_cap > frame_count
                              ? frame_count[7:0] : fifo_diff_cap);
    assign samp_stream_data = sfifo_rdata;
    reg have_frame;
    always @(posedge clk)
        samp_stream_avail <= have_frame && fifo_diff != 0;
    assign sfifo_ravail = have_frame && fifo_diff != 0; // XXX
    assign sfifo_raddr = fifo_pull_ptr;
    wire is_new_trigger;
    reg [ADDR_W-1:0] frame_preface;
    reg [31:0] frame_size;
    always @(posedge clk) begin
        if (samp_stream_avail && samp_stream_pull) begin
            fifo_pull_ptr <= fifo_pull_ptr + 1'b1;
            frame_count <= frame_count - 1;
        end else if (is_new_trigger) begin
            fifo_pull_ptr <= fifo_push_ptr - frame_preface;
            frame_count <= frame_size;
        end
    end
    always @(posedge clk) begin
        if (have_frame && (!frame_count || (!active && !fifo_diff)))
            have_frame <= 0;
        else if (is_new_trigger)
            have_frame <= 1;
    end

    // Trigger and active tracking
    wire is_command_set_status;
    always @(posedge clk) begin
        if (have_frame && fifo_diff == 13'h1ff0)
            active <= 0;
        else if (is_command_set_status)
            if (active || !have_frame)
                active <= wb_dat_i[0];
    end
    reg enable_trigger;
    always @(posedge clk) begin
        if (is_new_trigger)
            enable_trigger <= 0;
        else if (is_command_set_status)
            enable_trigger <= wb_dat_i[1];
    end
    reg force_trigger;
    always @(posedge clk) begin
        if (is_new_trigger)
            force_trigger <= 0;
        else if (is_command_set_status)
            force_trigger <= wb_dat_i[2];
    end
    wire want_trigger = enable_trigger && (force_trigger || trigger);
    assign is_new_trigger = want_trigger && active && !have_frame;

    // Command registers
    reg [31:0] reg_fifo_position;
    always @(posedge clk) begin
        if (is_command_set_status && wb_dat_i[7])
            reg_fifo_position <= fifo_push_counter;
        else if (is_new_trigger)
            reg_fifo_position <= fifo_push_counter;
    end
    wire is_command_set_frame_preface;
    always @(posedge clk) begin
        if (is_command_set_frame_preface && !active)
            if (!wb_adr_i[0])
                frame_preface[7:0] <= wb_dat_i;
            else
                frame_preface[ADDR_W-1:8] <= wb_dat_i[ADDR_W-9:0];
    end
    wire is_command_set_frame_size;
    always @(posedge clk) begin
        if (is_command_set_frame_size && !active)
            case (wb_adr_i[1:0])
            0: frame_size[7:0] <= wb_dat_i;
            1: frame_size[15:8] <= wb_dat_i;
            2: frame_size[23:16] <= wb_dat_i;
            3: frame_size[31:24] <= wb_dat_i;
            endcase
    end

    // Command handling
    wire is_command = wb_cyc_i && wb_stb_i && wb_we_i;
    assign is_command_set_status = is_command && wb_adr_i[3:0] == 0;
    assign is_command_set_frame_preface = is_command && wb_adr_i[3:1] == 1;
    assign is_command_set_frame_size = is_command && wb_adr_i[3:2] == 1;
    always @(*) begin
        case (wb_adr_i[3:0])
        default: wb_dat_o = {have_frame, force_trigger, enable_trigger, active};
        2: wb_dat_o = frame_preface[7:0];
        3: wb_dat_o = frame_preface[ADDR_W-1:8];

        4: wb_dat_o = frame_size[7:0];
        5: wb_dat_o = frame_size[15:8];
        6: wb_dat_o = frame_size[23:16];
        7: wb_dat_o = frame_size[31:24];

        8: wb_dat_o = reg_fifo_position[7:0];
        9: wb_dat_o = reg_fifo_position[15:8];
        10: wb_dat_o = reg_fifo_position[23:16];
        11: wb_dat_o = reg_fifo_position[31:24];

        12: wb_dat_o = frame_count[7:0];
        13: wb_dat_o = frame_count[15:8];
        14: wb_dat_o = frame_count[23:16];
        15: wb_dat_o = frame_count[31:24];
        endcase
    end
    assign wb_ack_o = 1;

endmodule
