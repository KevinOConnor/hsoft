// Forward a parsed request to wishbone bus and generate associated response
//
// Copyright (C) 2023  Kevin O'Connor <kevin@koconnor.net>
//
// This file may be distributed under the terms of the GNU GPLv3 license.

module wbcmd (
    input clk,

    input req_stb_i, input [5:0] req_seq_i, input req_we_i,
    input [15:0] req_adr_i, input [7:0] req_dat_i,

    output reg wb_stb_o, output wb_cyc_o, output reg wb_we_o,
    output reg [15:0] wb_adr_o,
    output reg [7:0] wb_dat_o,
    input [7:0] wb_dat_i,
    input wb_ack_i,

    output reg [7:0] resp_data, output [9:0] resp_count,
    output resp_avail, input resp_pull
    );

    // State tracking for command bus
    reg [5:0] recv_seq;
    wire valid_recv_seq = recv_seq == req_seq_i;
    always @(posedge clk) begin
        if (!wb_stb_o || wb_ack_i) begin
            // Not busy processing a command - check for new command
            if (req_stb_i && valid_recv_seq) begin
                wb_adr_o <= req_adr_i;
                wb_dat_o <= req_dat_i;
                wb_we_o <= req_we_i;
                recv_seq <= recv_seq + 1'b1;
                wb_stb_o <= 1;
            end else begin
                wb_stb_o <= 0;
            end
        end
    end
    assign wb_cyc_o = wb_stb_o;

    // Command response state tracking
    localparam REPLY_IDLE=2'd0, REPLY_SEQ=2'd1, REPLY_DATA=2'd2;
    reg [1:0] reply_state;
    reg [7:0] reply_data;
    always @(posedge clk) begin
        if (reply_state == REPLY_IDLE) begin
            if (wb_stb_o && wb_ack_i) begin
                // Command completed - generate a response
                reply_state <= REPLY_DATA;
                resp_data <= {1'b0, 1'b0, recv_seq};
                reply_data <= wb_dat_i;
            end else if (req_stb_i && !valid_recv_seq) begin
                // Incoming request had invalid sequence - send correct sequence
                reply_state <= REPLY_DATA;
                resp_data <= {1'b1, 1'b0, recv_seq};
                reply_data <= 8'b0;
            end
        end else if (resp_pull) begin
            reply_state <= reply_state - 1'b1;
            resp_data <= reply_data;
        end
    end
    assign resp_avail = reply_state != REPLY_IDLE;
    assign resp_count = reply_state;

endmodule
