// Generate serial messages for tx data streams
//
// Copyright (C) 2023  Kevin O'Connor <kevin@koconnor.net>
//
// This file may be distributed under the terms of the GNU GPLv3 license.

module msgencode (
    input clk,

    input [7:0] strm_data, input [9:0] strm_count,
    input [3:0] strm_id, input strm_avail, output strm_pull,

    output reg [3:0] send_id,

    output reg [7:0] tx_data, output tx_avail, input tx_pull
    );

    localparam SCAN_CHAR = 8'h7e;

    // Message generation state tracking
    localparam SEND_IDLE=3'd0, SEND_HDR=3'd1, SEND_SEQ=3'd2, SEND_DATALEN=3'd3,
               SEND_DATA=3'd4, SEND_CRC0=3'd5, SEND_CRC1=3'd6, SEND_TERM=3'd7;
    reg [2:0] send_state = SEND_IDLE;
    reg [9:0] send_count;
    reg [5:0] send_seq;
    always @(posedge clk) begin
        if (send_state == SEND_IDLE) begin
            // Tx idle - check for new stream to send
            if (strm_avail) begin
                send_state <= SEND_HDR;
                send_seq <= send_seq + 1'b1;
                send_id <= strm_id;
                send_count <= strm_count;
            end
        end else if (tx_pull) begin
            // A byte was sent, advance to next byte to send
            if (send_state == SEND_DATA)
                send_count <= send_count - 1'b1;

            if (send_state == SEND_TERM)
                send_state <= SEND_IDLE;
            else if (send_state == SEND_DATA && send_count != 1)
                send_state <= SEND_DATA;
            else
                send_state <= send_state + 1'b1;
        end
    end

    // Pull data from incoming stream
    assign strm_pull = tx_pull && (send_state == SEND_DATALEN
                                   || (send_state == SEND_DATA
                                       && send_count != 1));
    reg [7:0] send_data;
    always @(posedge clk)
        if (strm_pull)
            send_data <= strm_data;

    // Message CRC
    wire [15:0] send_crc;
    crc16ccitt crc16ccitt(
        .clk(clk),
        .clear(send_state == SEND_IDLE),
        .data(tx_data), .avail(tx_pull && send_state < SEND_CRC0),
        .crc(send_crc)
        );

    // Tx data generation
    always @(*) begin
        case (send_state)
        SEND_HDR:     tx_data = { 4'b0110, send_id };
        SEND_SEQ:     tx_data = { send_count[1:0], send_seq };
        SEND_DATALEN: tx_data = send_count[9:2];
        SEND_DATA:    tx_data = send_data;
        SEND_CRC0:    tx_data = send_crc[15:8];
        SEND_CRC1:    tx_data = send_crc[7:0];
        default:      tx_data = SCAN_CHAR;
        endcase
    end
    assign tx_avail = send_state != SEND_IDLE;

endmodule
