// Generate serial messages for tx data streams
//
// Copyright (C) 2023  Kevin O'Connor <kevin@koconnor.net>
//
// This file may be distributed under the terms of the GNU GPLv3 license.

module msgencode (
    input clk,

    input [31:0] strm_data, input [7:0] strm_count,
    input [3:0] strm_id, input strm_avail, output reg strm_pull,

    output reg [3:0] send_id,

    output reg [7:0] tx_data, output tx_avail, input tx_pull
    );

    localparam SCAN_CHAR = 8'h7e;

    // Message generation state tracking
    localparam SEND_IDLE=4'd0, SEND_HDR=4'd1, SEND_SEQ=4'd2, SEND_COUNT=4'd3,
               SEND_DATA0=4'd4, SEND_DATA1=4'd5, SEND_DATA2=4'd6,
               SEND_DATA3=4'd7, SEND_CRC0=4'd8, SEND_CRC1=4'd9, SEND_TERM=4'd10;
    reg [3:0] send_state = SEND_IDLE;
    reg [7:0] send_count;
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
            if (send_state == SEND_DATA3)
                send_count <= send_count - 1'b1;

            if (send_state == SEND_TERM)
                send_state <= SEND_IDLE;
            else if (send_state == SEND_DATA3 && send_count != 1)
                send_state <= SEND_DATA0;
            else
                send_state <= send_state + 1'b1;
        end
    end

    // Pull 32bits of data from incoming stream
    wire need_strm_pull = tx_pull && (send_state == SEND_COUNT
                                      || (send_state == SEND_DATA3
                                          && send_count != 1));
    always @(posedge clk)
        strm_pull <= need_strm_pull;
    reg [31:0] send_data;
    always @(posedge clk)
        if (need_strm_pull)
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
        SEND_HDR:   tx_data = { 4'b0110, send_id };
        SEND_SEQ:   tx_data = send_seq;
        SEND_COUNT: tx_data = send_count[7:0];
        SEND_DATA0: tx_data = send_data[7:0];
        SEND_DATA1: tx_data = send_data[15:8];
        SEND_DATA2: tx_data = send_data[23:16];
        SEND_DATA3: tx_data = send_data[31:24];
        SEND_CRC0:  tx_data = send_crc[15:8];
        SEND_CRC1:  tx_data = send_crc[7:0];
        default:    tx_data = SCAN_CHAR;
        endcase
    end
    assign tx_avail = send_state != SEND_IDLE;

endmodule
