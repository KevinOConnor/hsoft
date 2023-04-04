// Select sample to add to samples queue
//
// Copyright (C) 2023  Kevin O'Connor <kevin@koconnor.net>
//
// This file may be distributed under the terms of the GNU GPLv3 license.

module sampselect #(
    parameter NUM_SOURCES = 1
    )(
    input clk, input sq_active,
    output reg [31:0] sample, output reg sample_avail,

    input [32*NUM_SOURCES-1:0] sources, input [NUM_SOURCES-1:0] avails
    );

    // Storage for samples awaiting to be added to sample queue
    reg [32*NUM_SOURCES-1:0] data, next_data;
    reg [NUM_SOURCES-1:0] have_data, next_have_data;
    always @(posedge clk) begin
        data <= next_data;
        if (sq_active)
            have_data <= next_have_data;
        else
            have_data <= 0;
    end

    // Select channel to be sent to queue
    integer i;
    always @(*) begin
        sample = sources[0];
        sample_avail = 0;
        next_have_data = have_data;
        next_data = data;

        for (i=0; i<NUM_SOURCES; i=i+1) begin
            if (!sample_avail && have_data[i]) begin
                // Send this sample to the queue
                sample_avail = 1;
                next_have_data[i] = 0;
                sample = data[i*32 +: 32];
            end

            if (avails[i]) begin
                // New sample needs to be added to local storage
                next_data[i*32 +: 32] = sources[i*32 +: 32];
                next_have_data[i] = 1;
            end
        end
    end

endmodule
