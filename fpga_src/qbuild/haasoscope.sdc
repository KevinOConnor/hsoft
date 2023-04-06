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
create_clock -name clock_extadc1 -period "125MHz" [get_ports pin_extadc1_clk]
set_input_delay -clock clock_extadc1 -min 0 {pin_extadc1_ch*}
set_input_delay -clock clock_extadc1 -max 1 {pin_extadc1_ch*}
create_clock -name clock_extadc2 -period "125MHz" [get_ports pin_extadc2_clk]
set_input_delay -clock clock_extadc2 -min 0 {pin_extadc2_ch*}
set_input_delay -clock clock_extadc2 -max 5.5 {pin_extadc2_ch*}
set_max_delay -to {pin_extadc1_clk pin_extadc2_clk} 4
set_min_delay -to {pin_extadc1_clk pin_extadc2_clk} 0

# Note: The above extadc pin set_input_delay ranges were found
# experimentally.  Without tuned values the ADC may not be read
# atomically; in particular an ADC 8-bit value near 127,128
# (0b10000000,0b01111111) may be merged resulting in large reported
# spikes.

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
