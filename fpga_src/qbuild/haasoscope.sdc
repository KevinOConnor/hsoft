# Quartus software "Synopsis Design Constraints" file

create_clock -name clock_ext_osc -period "50MHz" [get_ports pin_ext_osc]
derive_clock_uncertainty
derive_pll_clocks

# UART (via USB full-speed chip)
create_clock -name clock_virtual_uart -period "1.5MHz"
set_input_delay -clock clock_virtual_uart 1 {pin_usb_uart_rx}
set_output_delay -clock clock_virtual_uart 1 {pin_usb_uart_tx}

# USB hi-speed
create_clock -name clock_usbhi -period "60MHz" [get_ports pin_usbhi_clkout]
set_input_delay -clock clock_usbhi -min 0 {pin_usbhi_rxfn pin_usbhi_txen pin_usbhi_adbus*}
set_input_delay -clock clock_usbhi -max 9 {pin_usbhi_rxfn pin_usbhi_txen pin_usbhi_adbus*}
set_output_delay -clock clock_usbhi -min 7.5 {pin_usbhi_oen pin_usbhi_rdn pin_usbhi_wrn pin_usbhi_pwrsavn pin_usbhi_siwun pin_usbhi_adbus*}
set_output_delay -clock clock_usbhi -max 0 {pin_usbhi_oen pin_usbhi_rdn pin_usbhi_wrn pin_usbhi_pwrsavn pin_usbhi_siwun pin_usbhi_adbus*}

# max19506 adcs

create_generated_clock -name clock_extadc1 -source {pll*clk[1]} [get_ports pin_extadc1_clk]
create_generated_clock -name clock_extadc2 -source {pll*clk[2]} [get_ports pin_extadc2_clk]
set_input_delay -clock clock_extadc1 0 {pin_extadc1_ch*}
set_input_delay -clock clock_extadc2 0 {pin_extadc2_ch*}
# Force Quartus to use IO registers for the extadc pins.  The output
# timing can be tuned at runtime in the max19506 via SPI
# configuration.
set_min_delay -from {pin_extadc1_ch*} 0.0
set_max_delay -from {pin_extadc1_ch*} 5.5
set_min_delay -from {pin_extadc2_ch*} 0.0
set_max_delay -from {pin_extadc2_ch*} 5.5

# max19506 spi
create_clock -name clock_virtual_adcspi -period "2MHz"
set_output_delay -clock clock_virtual_adcspi -min 10 {pin_adcspi_*}
set_output_delay -clock clock_virtual_adcspi -max 0 {pin_adcspi_*}

# i2c
create_clock -name clock_virtual_i2c -period "400KHz"
set_input_delay -clock clock_virtual_i2c 1 {pin_i2c_*}
set_output_delay -clock clock_virtual_i2c 1 {pin_i2c_*}

# Set clock groups
set_clock_groups -asynchronous -group {pll*} -group {clock_virtual_uart} -group {clock_usbhi} -group {clock_virtual_adcspi} -group {clock_virtual_i2c}
