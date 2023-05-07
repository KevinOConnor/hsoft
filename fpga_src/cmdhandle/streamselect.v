// Select the next tx message to send
//
// Copyright (C) 2023  Kevin O'Connor <kevin@koconnor.net>
//
// This file may be distributed under the terms of the GNU GPLv3 license.

module streamselect (
    input clk,

    input [7:0] resp_data, input [9:0] resp_count,
    input resp_avail, output resp_pull,

    input [7:0] samp_stream_data, input [9:0] samp_stream_count,
    input samp_stream_avail, output samp_stream_pull,

    output [7:0] strm_data, output [9:0] strm_count,
    output [3:0] strm_id, output strm_avail, input strm_pull,

    input [3:0] send_id
    );

    localparam STRM_ID_RESP = 1'd0, STRM_ID_SAMPLE = 1'd1;

    assign strm_avail = resp_avail || samp_stream_avail;
    assign strm_id = resp_avail ? STRM_ID_RESP : STRM_ID_SAMPLE;
    assign strm_count = resp_avail ? resp_count : samp_stream_count;
    assign samp_stream_pull = strm_pull && send_id == STRM_ID_SAMPLE;
    assign resp_pull = strm_pull && send_id == STRM_ID_RESP;
    assign strm_data = send_id == STRM_ID_RESP ? resp_data : samp_stream_data;

endmodule
