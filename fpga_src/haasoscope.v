// Top level haasoscope firmware file
//
// Copyright (C) 2023  Kevin O'Connor <kevin@koconnor.net>
//
// This file may be distributed under the terms of the GNU GPLv3 license.

module haasoscope (
    input pin_ext_osc,
    input pin_usb_uart_rx, output pin_usb_uart_tx,

    input pin_usbhi_rxfn, input pin_usbhi_txen, input pin_usbhi_clkout,
    output pin_usbhi_oen, output pin_usbhi_rdn, output pin_usbhi_wrn,
    output pin_usbhi_pwrsavn, output pin_usbhi_siwun,
    inout [7:0] pin_usbhi_adbus,

    output pin_extadc1_clk,
    input [7:0] pin_extadc1_cha, input [7:0] pin_extadc1_chb,
    output pin_extadc2_clk,
    input [7:0] pin_extadc2_cha, input [7:0] pin_extadc2_chb,

    output pin_adcspi_mosi, output pin_adcspi_sclk, output pin_adcspi_cs,

    inout pin_i2c_scl, inout pin_i2c_sda
    );

    // Main clock
    localparam CLOCK_FREQUENCY = 125000000;
    wire clk;
    main_pll pll(.inclk0(pin_ext_osc), .c0(clk));

    // Reset signal
    wire rst;
    syncreset synchronous_reset(.clk(clk), .rst(rst));

    // Command serial port
    localparam USB_SERIAL_BAUD = 1500000;
    wire uart_rx_avail;
    wire [7:0] uart_rx_data;
    rxuartlite #(
        .CLOCKS_PER_BAUD(CLOCK_FREQUENCY / USB_SERIAL_BAUD)
        ) command_rx_serial(
        .i_clk(clk), .i_uart_rx(pin_usb_uart_rx),
        .o_wr(uart_rx_avail), .o_data(uart_rx_data)
        );
    wire uart_tx_avail, uart_tx_busy;
    wire [7:0] uart_tx_data;
    txuartlite #(
        .CLOCKS_PER_BAUD(CLOCK_FREQUENCY / USB_SERIAL_BAUD)
        ) command_tx_serial(
        .i_clk(clk), .o_uart_tx(pin_usb_uart_tx),
        .i_wr(uart_tx_avail), .i_data(uart_tx_data), .o_busy(uart_tx_busy)
        );

    // USB hi-speed port
    wire [7:0] usbhi_data_in, usbhi_data_out;
    wire usbhi_data_out_enable;
    assign pin_usbhi_adbus = usbhi_data_out_enable ? usbhi_data_out : 8'bz;
    assign usbhi_data_in = pin_usbhi_adbus;
    wire [7:0] usbhi_rx_data;
    wire usbhi_rx_avail;
    wire [7:0] usbhi_tx_data;
    wire usbhi_tx_avail, usbhi_tx_pull;
    ft232h usbhi_serial(
        .clk(clk), .rst(rst),

        .ft_clkout(pin_usbhi_clkout), .ft_oen(pin_usbhi_oen),
        .ft_rxfn(pin_usbhi_rxfn), .ft_rdn(pin_usbhi_rdn),
        .ft_data_in(usbhi_data_in),
        .ft_txen(pin_usbhi_txen), .ft_wrn(pin_usbhi_wrn),
        .ft_siwun(pin_usbhi_siwun), .ft_pwrsavn(pin_usbhi_pwrsavn),
        .ft_data_out(usbhi_data_out),
        .ft_data_out_enable(usbhi_data_out_enable),

        .rx_data(usbhi_rx_data), .rx_avail(usbhi_rx_avail),
        .tx_data(usbhi_tx_data), .tx_avail(usbhi_tx_avail),
        .tx_pull(usbhi_tx_pull)
        );

    // Command building
    wire [31:0] samp_stream_data;
    wire [7:0] samp_stream_count;
    wire samp_stream_avail, samp_stream_pull;
    wire wb_stb_o, wb_cyc_o, wb_we_o;
    wire [15:0] wb_adr_o;
    wire [7:0] wb_dat_o;
    wire [7:0] wb_dat_i;
    wire wb_ack_i;
    serialcmd command_builder(
        .clk(clk),

        .uart_rx_data(uart_rx_data), .uart_rx_avail(uart_rx_avail),
        .uart_tx_data(uart_tx_data), .uart_tx_avail(uart_tx_avail),
        .uart_tx_pull(!uart_tx_busy),

        .usbhi_rx_data(usbhi_rx_data), .usbhi_rx_avail(usbhi_rx_avail),
        .usbhi_tx_data(usbhi_tx_data), .usbhi_tx_avail(usbhi_tx_avail),
        .usbhi_tx_pull(usbhi_tx_pull),

        .samp_stream_data(samp_stream_data),
        .samp_stream_count(samp_stream_count),
        .samp_stream_avail(samp_stream_avail),
        .samp_stream_pull(samp_stream_pull),

        .wb_stb_o(wb_stb_o), .wb_cyc_o(wb_cyc_o), .wb_we_o(wb_we_o),
        .wb_adr_o(wb_adr_o), .wb_dat_o(wb_dat_o),
        .wb_dat_i(wb_dat_i), .wb_ack_i(wb_ack_i)
        );

    // External MAX19506 ADCs
    wire sq_active;
    assign pin_extadc1_clk = clk;
    wire ch0_trigger;
    wire [31:0] extadc_ch0_sample;
    wire extadc_ch0_sample_avail;
    wire ch0_wb_stb_i, ch0_wb_cyc_i, ch0_wb_we_i;
    wire [15:0] ch0_wb_adr_i;
    wire [7:0] ch0_wb_dat_i;
    wire [7:0] ch0_wb_dat_o;
    wire ch0_wb_ack_o;
    adcchannel adc_channel0(
        .clk(clk),
        .adc_clk(pin_extadc1_clk), .adc_ch(pin_extadc1_cha),

        .sq_active(sq_active), .sq_trigger(ch0_trigger),

        .sample(extadc_ch0_sample), .sample_avail(extadc_ch0_sample_avail),

        .wb_stb_i(ch0_wb_stb_i), .wb_cyc_i(ch0_wb_cyc_i),
        .wb_we_i(ch0_wb_we_i),
        .wb_adr_i(ch0_wb_adr_i), .wb_dat_i(ch0_wb_dat_i),
        .wb_dat_o(ch0_wb_dat_o), .wb_ack_o(ch0_wb_ack_o)
        );
    wire ch1_trigger;
    wire [31:0] extadc_ch1_sample;
    wire extadc_ch1_sample_avail;
    wire ch1_wb_stb_i, ch1_wb_cyc_i, ch1_wb_we_i;
    wire [15:0] ch1_wb_adr_i;
    wire [7:0] ch1_wb_dat_i;
    wire [7:0] ch1_wb_dat_o;
    wire ch1_wb_ack_o;
    adcchannel adc_channel1(
        .clk(clk),
        .adc_clk(pin_extadc1_clk), .adc_ch(pin_extadc1_chb),

        .sq_active(sq_active), .sq_trigger(ch1_trigger),

        .sample(extadc_ch1_sample), .sample_avail(extadc_ch1_sample_avail),

        .wb_stb_i(ch1_wb_stb_i), .wb_cyc_i(ch1_wb_cyc_i),
        .wb_we_i(ch1_wb_we_i),
        .wb_adr_i(ch1_wb_adr_i), .wb_dat_i(ch1_wb_dat_i),
        .wb_dat_o(ch1_wb_dat_o), .wb_ack_o(ch1_wb_ack_o)
        );
    assign pin_extadc2_clk = clk;
    wire ch2_trigger;
    wire [31:0] extadc_ch2_sample;
    wire extadc_ch2_sample_avail;
    wire ch2_wb_stb_i, ch2_wb_cyc_i, ch2_wb_we_i;
    wire [15:0] ch2_wb_adr_i;
    wire [7:0] ch2_wb_dat_i;
    wire [7:0] ch2_wb_dat_o;
    wire ch2_wb_ack_o;
    adcchannel adc_channel2(
        .clk(clk),
        .adc_clk(pin_extadc2_clk), .adc_ch(pin_extadc2_cha),

        .sq_active(sq_active), .sq_trigger(ch2_trigger),

        .sample(extadc_ch2_sample), .sample_avail(extadc_ch2_sample_avail),

        .wb_stb_i(ch2_wb_stb_i), .wb_cyc_i(ch2_wb_cyc_i),
        .wb_we_i(ch2_wb_we_i),
        .wb_adr_i(ch2_wb_adr_i), .wb_dat_i(ch2_wb_dat_i),
        .wb_dat_o(ch2_wb_dat_o), .wb_ack_o(ch2_wb_ack_o)
        );
    wire ch3_trigger;
    wire [31:0] extadc_ch3_sample;
    wire extadc_ch3_sample_avail;
    wire ch3_wb_stb_i, ch3_wb_cyc_i, ch3_wb_we_i;
    wire [15:0] ch3_wb_adr_i;
    wire [7:0] ch3_wb_dat_i;
    wire [7:0] ch3_wb_dat_o;
    wire ch3_wb_ack_o;
    adcchannel adc_channel3(
        .clk(clk),
        .adc_clk(pin_extadc2_clk), .adc_ch(pin_extadc2_chb),

        .sq_active(sq_active), .sq_trigger(ch3_trigger),

        .sample(extadc_ch3_sample), .sample_avail(extadc_ch3_sample_avail),

        .wb_stb_i(ch3_wb_stb_i), .wb_cyc_i(ch3_wb_cyc_i),
        .wb_we_i(ch3_wb_we_i),
        .wb_adr_i(ch3_wb_adr_i), .wb_dat_i(ch3_wb_dat_i),
        .wb_dat_o(ch3_wb_dat_o), .wb_ack_o(ch3_wb_ack_o)
        );

    // Measurement sample queue
    wire sq_trigger;
    trigselect #(
        .NUM_SOURCES(4)
        ) trigger_selector(
        .clk(clk), .sq_trigger(sq_trigger),
        .triggers({ch3_trigger, ch2_trigger, ch1_trigger, ch0_trigger})
        );
    wire [31:0] sq_sample;
    wire sq_sample_avail;
    sampselect #(
        .NUM_SOURCES(4)
        ) sample_selector(
        .clk(clk), .sq_active(sq_active),
        .sample(sq_sample), .sample_avail(sq_sample_avail),

        .sources({extadc_ch3_sample, extadc_ch2_sample,
                  extadc_ch1_sample, extadc_ch0_sample}),
        .avails({extadc_ch3_sample_avail, extadc_ch2_sample_avail,
                 extadc_ch1_sample_avail, extadc_ch0_sample_avail})
        );
    wire sq_wb_stb_i, sq_wb_cyc_i, sq_wb_we_i;
    wire [15:0] sq_wb_adr_i;
    wire [7:0] sq_wb_dat_i;
    wire [7:0] sq_wb_dat_o;
    wire sq_wb_ack_o;
    sampleq sample_queue(
        .clk(clk),
        .sample(sq_sample), .sample_avail(sq_sample_avail), .active(sq_active),
        .trigger(sq_trigger),

        .samp_stream_data(samp_stream_data),
        .samp_stream_count(samp_stream_count),
        .samp_stream_avail(samp_stream_avail),
        .samp_stream_pull(samp_stream_pull),

        .wb_stb_i(sq_wb_stb_i), .wb_cyc_i(sq_wb_cyc_i),
        .wb_we_i(sq_wb_we_i),
        .wb_adr_i(sq_wb_adr_i), .wb_dat_i(sq_wb_dat_i),
        .wb_dat_o(sq_wb_dat_o), .wb_ack_o(sq_wb_ack_o)
        );

    // MAX19506 SPI message sending
    wire adcspi_wb_stb_i, adcspi_wb_cyc_i, adcspi_wb_we_i;
    wire [7:0] adcspi_wb_adr_i;
    wire [7:0] adcspi_wb_dat_i;
    wire [7:0] adcspi_wb_dat_o;
    wire adcspi_wb_ack_o;
    maxadcspi #(
        .CLOCK_FREQUENCY(CLOCK_FREQUENCY)
        ) maxadc_command(
        .clk(clk),
        .mosi(pin_adcspi_mosi), .sclk(pin_adcspi_sclk), .cs(pin_adcspi_cs),

        .wb_stb_i(adcspi_wb_stb_i), .wb_cyc_i(adcspi_wb_cyc_i),
        .wb_we_i(adcspi_wb_we_i),
        .wb_adr_i(adcspi_wb_adr_i), .wb_dat_i(adcspi_wb_dat_i),
        .wb_dat_o(adcspi_wb_dat_o), .wb_ack_o(adcspi_wb_ack_o)
        );

    // I2C (for dac and gpio expanders)
    wire i2c_scl_o, i2c_scl_oen, i2c_scl_i, i2c_sda_o, i2c_sda_oen, i2c_sda_i;
    assign pin_i2c_scl = i2c_scl_oen ? 1'bz : i2c_scl_o;
    assign i2c_scl_i = pin_i2c_scl;
    assign pin_i2c_sda = i2c_sda_oen ? 1'bz : i2c_sda_o;
    assign i2c_sda_i = pin_i2c_sda;
    wire i2c_wb_stb_i, i2c_wb_cyc_i, i2c_wb_we_i;
    wire [7:0] i2c_wb_adr_i;
    wire [7:0] i2c_wb_dat_i;
    wire [7:0] i2c_wb_dat_o;
    wire i2c_wb_ack_o;
    i2c_master_top i2c(
        .scl_pad_i(i2c_scl_i),
        .scl_pad_o(i2c_scl_o), .scl_padoen_o(i2c_scl_oen),
        .sda_pad_i(i2c_sda_i),
        .sda_pad_o(i2c_sda_o), .sda_padoen_o(i2c_sda_oen),

        .wb_clk_i(clk), .wb_rst_i(rst),
        .wb_stb_i(i2c_wb_stb_i), .wb_cyc_i(i2c_wb_cyc_i), .wb_we_i(i2c_wb_we_i),
        .wb_adr_i(i2c_wb_adr_i), .wb_dat_i(i2c_wb_dat_i),
        .wb_dat_o(i2c_wb_dat_o), .wb_ack_o(i2c_wb_ack_o)
        );

    // Bus routing
    busdispatch bus_dispatcher(
        .clk(clk),

        .wb_stb_i(wb_stb_o), .wb_cyc_i(wb_cyc_o), .wb_we_i(wb_we_o),
        .wb_adr_i(wb_adr_o), .wb_dat_i(wb_dat_o), .wb_dat_o(wb_dat_i),
        .wb_ack_o(wb_ack_i),

        .ch0_wb_stb_o(ch0_wb_stb_i), .ch0_wb_cyc_o(ch0_wb_cyc_i),
        .ch0_wb_we_o(ch0_wb_we_i),
        .ch0_wb_adr_o(ch0_wb_adr_i), .ch0_wb_dat_o(ch0_wb_dat_i),
        .ch0_wb_dat_i(ch0_wb_dat_o), .ch0_wb_ack_i(ch0_wb_ack_o),

        .ch1_wb_stb_o(ch1_wb_stb_i), .ch1_wb_cyc_o(ch1_wb_cyc_i),
        .ch1_wb_we_o(ch1_wb_we_i),
        .ch1_wb_adr_o(ch1_wb_adr_i), .ch1_wb_dat_o(ch1_wb_dat_i),
        .ch1_wb_dat_i(ch1_wb_dat_o), .ch1_wb_ack_i(ch1_wb_ack_o),

        .ch2_wb_stb_o(ch2_wb_stb_i), .ch2_wb_cyc_o(ch2_wb_cyc_i),
        .ch2_wb_we_o(ch2_wb_we_i),
        .ch2_wb_adr_o(ch2_wb_adr_i), .ch2_wb_dat_o(ch2_wb_dat_i),
        .ch2_wb_dat_i(ch2_wb_dat_o), .ch2_wb_ack_i(ch2_wb_ack_o),

        .ch3_wb_stb_o(ch3_wb_stb_i), .ch3_wb_cyc_o(ch3_wb_cyc_i),
        .ch3_wb_we_o(ch3_wb_we_i),
        .ch3_wb_adr_o(ch3_wb_adr_i), .ch3_wb_dat_o(ch3_wb_dat_i),
        .ch3_wb_dat_i(ch3_wb_dat_o), .ch3_wb_ack_i(ch3_wb_ack_o),

        .sq_wb_stb_o(sq_wb_stb_i), .sq_wb_cyc_o(sq_wb_cyc_i),
        .sq_wb_we_o(sq_wb_we_i),
        .sq_wb_adr_o(sq_wb_adr_i), .sq_wb_dat_o(sq_wb_dat_i),
        .sq_wb_dat_i(sq_wb_dat_o), .sq_wb_ack_i(sq_wb_ack_o),

        .adcspi_wb_stb_o(adcspi_wb_stb_i), .adcspi_wb_cyc_o(adcspi_wb_cyc_i),
        .adcspi_wb_we_o(adcspi_wb_we_i),
        .adcspi_wb_adr_o(adcspi_wb_adr_i), .adcspi_wb_dat_o(adcspi_wb_dat_i),
        .adcspi_wb_dat_i(adcspi_wb_dat_o), .adcspi_wb_ack_i(adcspi_wb_ack_o),

        .i2c_wb_stb_o(i2c_wb_stb_i), .i2c_wb_cyc_o(i2c_wb_cyc_i),
        .i2c_wb_we_o(i2c_wb_we_i),
        .i2c_wb_adr_o(i2c_wb_adr_i), .i2c_wb_dat_o(i2c_wb_dat_i),
        .i2c_wb_dat_i(i2c_wb_dat_o), .i2c_wb_ack_i(i2c_wb_ack_o)
        );

endmodule
