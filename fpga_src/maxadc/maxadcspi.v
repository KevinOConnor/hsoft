// MAX19506 spi message sending
//
// Copyright (C) 2023  Kevin O'Connor <kevin@koconnor.net>
//
// This file may be distributed under the terms of the GNU GPLv3 license.

module maxadcspi #(
    parameter CLOCK_FREQUENCY = 125000000
    )(
    input clk,
    output reg mosi, output reg sclk, output reg cs,

    input wb_stb_i, input wb_cyc_i, input wb_we_i,
    input [7:0] wb_adr_i,
    input [7:0] wb_dat_i,
    output [7:0] wb_dat_o,
    output wb_ack_o
    );

    // SPI bit rate
    localparam MAX_FREQ = 2000000;
    localparam CNTBITS = $clog2(CLOCK_FREQUENCY / MAX_FREQ);
    reg [(CNTBITS-1):0] cnt;
    reg [(CNTBITS-1):0] next_cnt;
    always @(*)
        next_cnt = cnt + 1'b1;
    always @(posedge clk)
        cnt <= next_cnt;
    wire is_rising_edge = !cnt[CNTBITS-1] && next_cnt[CNTBITS-1];
    wire is_falling_edge = cnt[CNTBITS-1] && !next_cnt[CNTBITS-1];

    // Transmit state tracking
    localparam S_IDLE=0, S_NEED_CS=1, S_TX_DATA=2, S_END=3;
    reg [1:0] state;
    reg [3:0] tx_cnt;
    wire is_command_start;
    always @(posedge clk) begin
        if (state == S_IDLE) begin
            tx_cnt <= 0;
            if (is_command_start)
                state <= S_NEED_CS;
        end else if (is_rising_edge) begin
            case (state)
            S_NEED_CS: begin
                state <= S_TX_DATA;
            end
            S_TX_DATA: begin
                if (tx_cnt == 15)
                    state <= S_END;
                tx_cnt <= tx_cnt + 1'b1;
            end
            S_END: begin
                state <= S_IDLE;
            end
            endcase
        end
    end

    // SPI signal assignment
    always @(posedge clk) begin
        if (state == S_IDLE || (state == S_END && is_rising_edge))
            cs <= 1;
        else if (state == S_NEED_CS && is_rising_edge)
            cs <= 0;
    end
    always @(posedge clk) begin
        if (state != S_TX_DATA || is_falling_edge)
            sclk <= 0;
        else if (is_rising_edge)
            sclk <= 1;
    end
    wire is_command_set_data;
    reg [15:0] tx_data;
    always @(posedge clk) begin
        if (state == S_IDLE && is_command_set_data) begin
            if (wb_adr_i[0])
                tx_data[7:0] <= wb_dat_i;
            else
                tx_data[15:8] <= wb_dat_i;
        end else if (state == S_TX_DATA && is_falling_edge) begin
            mosi <= tx_data[15];
            tx_data <= { tx_data[14:0], 1'b0 };
        end
    end

    // Wishbone command handling
    wire is_command = wb_cyc_i && wb_stb_i && wb_we_i;
    assign is_command_start = is_command && wb_adr_i[1:0] == 0 && wb_dat_i[0];
    assign is_command_set_data = is_command && wb_adr_i[1];
    assign wb_dat_o = state;
    assign wb_ack_o = 1;

endmodule
