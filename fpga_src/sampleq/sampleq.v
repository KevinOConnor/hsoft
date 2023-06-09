// Queue for measurement samples
//
// Copyright (C) 2023  Kevin O'Connor <kevin@koconnor.net>
//
// This file may be distributed under the terms of the GNU GPLv3 license.

module sampleq #(
    parameter QUEUE_SIZE = 128,
    parameter SAMPLE_W = 72
    )(
    input clk,

    input [SAMPLE_W-1:0] sample, input sample_avail, output reg active,
    input trigger,

    output reg [7:0] samp_stream_data, output [9:0] samp_stream_count,
    output reg samp_stream_avail, input samp_stream_pull,

    input wb_stb_i, input wb_cyc_i, input wb_we_i,
    input [15:0] wb_adr_i,
    input [7:0] wb_dat_i,
    output reg [7:0] wb_dat_o,
    output wb_ack_o
    );

    localparam ADDR_W = $clog2(QUEUE_SIZE);

    // Memory storage for samples
    wire [ADDR_W-1:0] sfifo_raddr;
    wire [SAMPLE_W-1:0] sfifo_rdata;
    wire sfifo_ravail;
    wire [ADDR_W-1:0] sfifo_waddr;
    wire [SAMPLE_W-1:0] sfifo_wdata;
    wire sfifo_wavail;
    sampfifo #(
        .QUEUE_SIZE(QUEUE_SIZE),
        .SAMPLE_W(SAMPLE_W),
        .ADDR_W(ADDR_W)
        ) sample_fifo(
        .clk(clk),
        .raddr(sfifo_raddr), .rdata(sfifo_rdata), .ravail(sfifo_ravail),
        .waddr(sfifo_waddr), .wdata(sfifo_wdata), .wavail(sfifo_wavail)
        );

    // Add incoming sample to sample fifo
    assign sfifo_wdata = sample;
    assign sfifo_wavail = sample_avail && active;
    reg [31:0] fifo_push_counter = 0;
    reg [ADDR_W-1:0] fifo_push_ptr = 0;
    always @(posedge clk) begin
        if (sfifo_wavail) begin
            fifo_push_counter <= fifo_push_counter + 1'b1;
            if (fifo_push_ptr + 1'b1 != QUEUE_SIZE)
                fifo_push_ptr <= fifo_push_ptr + 1'b1;
            else
                fifo_push_ptr <= 0;
        end
    end
    assign sfifo_waddr = fifo_push_ptr;

    // Is there an available "frame" to be sent to host?
    wire is_new_trigger, is_frame_completed;
    reg have_frame;
    always @(posedge clk) begin
        if (is_new_trigger)
            have_frame <= 1;
        else if (is_frame_completed)
            have_frame <= 0;
    end

    // Manage fifo pull position
    reg [31:0] fifo_pull_counter;
    reg [ADDR_W-1:0] fifo_pull_ptr;
    wire [31:0] fifo_diff32 = fifo_push_counter - fifo_pull_counter;
    wire [ADDR_W-1:0] fifo_diff = fifo_diff32[ADDR_W-1:0];
    reg [ADDR_W-1:0] frame_preface;
    wire [ADDR_W:0] next_trigger_pull_ptr = fifo_push_ptr - frame_preface;
    wire [31:0] wrap_pull_ptr = QUEUE_SIZE + next_trigger_pull_ptr;
    reg [31:0] frame_size;
    reg [31:0] frame_count;
    wire is_sample_pull;
    always @(posedge clk) begin
        if (is_new_trigger) begin
            fifo_pull_counter <= fifo_push_counter - frame_preface;
            if (next_trigger_pull_ptr[ADDR_W])
                // Queue rollover - set ptr relative to end of queue
                fifo_pull_ptr <= wrap_pull_ptr[ADDR_W-1:0];
            else
                fifo_pull_ptr <= next_trigger_pull_ptr[ADDR_W-1:0];
            frame_count <= frame_size;
        end else if (is_sample_pull) begin
            fifo_pull_counter <= fifo_pull_counter + 1;
            if (fifo_pull_ptr + 1 != QUEUE_SIZE)
                fifo_pull_ptr <= fifo_pull_ptr + 1'b1;
            else
                fifo_pull_ptr <= 0;
            frame_count <= frame_count - 1;
        end
    end
    assign is_frame_completed = !frame_count || (!active && !fifo_diff);

    // Send extracted fifo data to command stream
    reg [ADDR_W-1:0] avail_fifo_count;
    always @(posedge clk)
        avail_fifo_count = (fifo_diff > frame_count
                            ? frame_count[ADDR_W-1:0] : fifo_diff);
    assign samp_stream_count = (avail_fifo_count > 96 ? 8'd96
                                : avail_fifo_count[7:0]) * 10'd9;
    wire can_pull = have_frame && fifo_diff != 0;
    always @(posedge clk)
        samp_stream_avail <= can_pull && (!active || fifo_diff >= 48
                                          || fifo_diff > frame_count);
    localparam LAST_BYTE = (SAMPLE_W / 8) - 1;
    reg [3:0] stream_byte_pos = 0;
    always @(posedge clk)
        if (samp_stream_pull)
            stream_byte_pos <= (stream_byte_pos == LAST_BYTE ? 1'b0
                                : stream_byte_pos + 1'b1);
    assign is_sample_pull = (can_pull && samp_stream_pull
                             && stream_byte_pos == 0);
    reg [SAMPLE_W-1:0] send_cache; // sfifo read takes 2 cycles - stagger reads
    always @(posedge clk)
        if (stream_byte_pos == 0
            || (samp_stream_pull && stream_byte_pos == LAST_BYTE))
            send_cache <= sfifo_rdata;
    always @(*) begin
        case (stream_byte_pos)
        default: samp_stream_data = send_cache[7:0];
        1: samp_stream_data = send_cache[15:8];
        2: samp_stream_data = send_cache[23:16];
        3: samp_stream_data = send_cache[31:24];
        4: samp_stream_data = send_cache[39:32];
        5: samp_stream_data = send_cache[47:40];
        6: samp_stream_data = send_cache[55:48];
        7: samp_stream_data = send_cache[63:56];
        8: samp_stream_data = send_cache[71:64];
        endcase
    end
    assign sfifo_ravail = have_frame; // Avoids read/write to same addr
    assign sfifo_raddr = fifo_pull_ptr;

    // Trigger and active tracking
    wire is_command_set_status;
    always @(posedge clk) begin
        if (have_frame && fifo_diff == QUEUE_SIZE - 2)
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
