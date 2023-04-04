// Parse commands from serial port
//
// Copyright (C) 2023  Kevin O'Connor <kevin@koconnor.net>
//
// This file may be distributed under the terms of the GNU GPLv3 license.

module msgparse (
    input clk, input [7:0] rx_data, input rx_avail,

    output stb_o, output reg [5:0] seq_o, output reg we_o,
    output reg [15:0] adr_o, output reg [7:0] dat_o
    );

    localparam REQ_HDR = 8'h52;
    localparam SCAN_CHAR = 8'h7e;

    // State tracking for input message reading
    wire [15:0] recv_crc;
    localparam GET_HDR=0, GET_SEQ=1, GET_COUNT=2,
               GET_DATA0=3, GET_DATA1=4, GET_DATA2=5, GET_DATA3=6,
               GET_CRC0=7, GET_CRC1=8, GET_TERM=9, SCAN_TERM=10;
    reg [3:0] recv_state = GET_HDR;
    always @(posedge clk) begin
        if (rx_avail) begin
            case (recv_state)
            GET_HDR: begin
                if (rx_data == REQ_HDR) begin
                    recv_state <= GET_SEQ;
                end else begin
                    recv_state <= SCAN_TERM;
                end
            end
            GET_SEQ: begin
                if (!rx_data[7:6]) begin
                    seq_o <= rx_data[5:0];
                    recv_state <= GET_COUNT;
                end else begin
                    recv_state <= SCAN_TERM;
                end
            end
            GET_COUNT: begin
                if (rx_data == 1'b1) begin
                    recv_state <= GET_DATA0;
                end else begin
                    recv_state <= SCAN_TERM;
                end
            end
            GET_DATA0: begin
                if (!rx_data[6:0]) begin
                    we_o <= rx_data[7];
                    recv_state <= GET_DATA1;
                end else begin
                    recv_state <= SCAN_TERM;
                end
            end
            GET_DATA1: begin
                adr_o[7:0] <= rx_data;
                recv_state <= GET_DATA2;
            end
            GET_DATA2: begin
                adr_o[15:8] <= rx_data;
                recv_state <= GET_DATA3;
            end
            GET_DATA3: begin
                dat_o <= rx_data;
                recv_state <= GET_CRC0;
            end
            GET_CRC0: begin
                if (rx_data == recv_crc[15:8])
                    recv_state <= GET_CRC1;
                else
                    recv_state <= SCAN_TERM;
            end
            GET_CRC1: begin
                if (rx_data == recv_crc[7:0])
                    recv_state <= GET_TERM;
                else
                    recv_state <= SCAN_TERM;
            end
            GET_TERM: begin
                if (rx_data == SCAN_CHAR) begin
                    recv_state <= GET_HDR;
                end else begin
                    recv_state <= SCAN_TERM;
                end
            end
            SCAN_TERM: begin
                if (rx_data == SCAN_CHAR)
                    recv_state <= GET_HDR;
            end
            endcase
        end
    end
    assign stb_o = rx_avail && recv_state == GET_TERM && rx_data == SCAN_CHAR;

    crc16ccitt crc16ccitt(
        .clk(clk),
        .clear(recv_state == GET_TERM || recv_state == SCAN_TERM),
        .data(rx_data), .avail(rx_avail && recv_state != GET_CRC0),
        .crc(recv_crc)
        );

endmodule
