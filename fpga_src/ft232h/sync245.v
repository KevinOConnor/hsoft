// Support for "ft235 synchronous" protocol on ft232h chips
//
// Copyright (C) 2023  Kevin O'Connor <kevin@koconnor.net>
//
// This file may be distributed under the terms of the GNU GPLv3 license.

module sync245(
    input ft_clkout, output ft_oen,
    output ft_pwrsavn, output ft_siwun,
    input ft_rxfn, output ft_rdn, input [7:0] ft_data_in,
    input ft_txen, output ft_wrn, output [7:0] ft_data_out,
    output ft_data_out_enable,

    output [7:0] rx_data, output rx_avail, input rx_pull,
    input [7:0] tx_data, input tx_avail, output tx_pull
    );

    // State tracking for input/output switching
    localparam S_TRANSIT_READ=0, S_READ=1, S_TRANSIT_WRITE=2, S_WRITE=3;
    reg [1:0] state;
    always @(posedge ft_clkout) begin
        case (state)
        S_TRANSIT_READ: begin
            state <= S_READ;
        end
        S_READ: begin
            if (tx_avail && !ft_txen && (!rx_pull || ft_rxfn))
                state <= S_TRANSIT_WRITE;
        end
        S_TRANSIT_WRITE: begin
            state <= S_WRITE;
        end
        S_WRITE: begin
            if (rx_pull && !ft_rxfn && (!tx_avail || ft_txen))
                state <= S_TRANSIT_READ;
        end
        endcase
    end

    // Signal assignment
    assign ft_oen = state==S_TRANSIT_WRITE || state==S_WRITE;
    assign ft_data_out_enable = state==S_WRITE;

    assign rx_data = ft_data_in;
    assign ft_rdn = !(state==S_READ && rx_pull);
    assign rx_avail = !ft_rxfn && !ft_rdn;

    assign ft_data_out = tx_data;
    assign ft_wrn = !(state==S_WRITE && tx_avail);
    assign tx_pull = !ft_txen && !ft_wrn;

    // Transmit flush indicator
    reg need_flush = 0;
    always @(posedge ft_clkout) begin
        if (tx_pull)
            need_flush <= 1;
        else if (!ft_siwun)
            need_flush <= 0;
    end
    reg siwun = 1;
    always @(posedge ft_clkout)
        siwun <= !(need_flush && !ft_txen && !tx_avail && !rx_avail);
    assign ft_siwun = siwun;

    // Power enable
    reg pwr_en = 0;
    always @(posedge ft_clkout)
        pwr_en <= 1;
    assign ft_pwrsavn = pwr_en;

endmodule
