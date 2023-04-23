# Definitions for the fpga registers
#
# Copyright (C) 2023  Kevin O'Connor <kevin@koconnor.net>
#
# This file may be distributed under the terms of the GNU GPLv3 license.

# Each module start address is defined as:
#  "module_name": (start_address, registers)
# Where 'registers' is defined as:
#  {"register_name": (address_offset, register_byte_size), ...}
FPGA_MODULES = {}

# ADC channel configuration
ADC_CHANNEL_REGS = {
    # triggers
    "trigger": (0x00, 1),
    "thresh": (0x01, 1),
    # sample adc accumulate
    "status": (0x20, 1),
    "acc_cnt": (0x21, 1),
    "sum_mask": (0x22, 2),
    "initial_sum": (0x24, 2),
}
FPGA_MODULES["ch0"] = (0x80, ADC_CHANNEL_REGS)
FPGA_MODULES["ch1"] = (0x81, ADC_CHANNEL_REGS)
FPGA_MODULES["ch2"] = (0x82, ADC_CHANNEL_REGS)
FPGA_MODULES["ch3"] = (0x83, ADC_CHANNEL_REGS)

# Sample queue configuration
SAMPLE_QUEUE_REGS = {
    "status": (0x00, 1),
    "frame_preface": (0x02, 2),
    "frame_size": (0x04, 4),
    "reg_fifo_position": (0x08, 4),
    "frame_count": (0x0c, 4),
}
FPGA_MODULES["sq"] = (0x87, SAMPLE_QUEUE_REGS)

# Code version module
VERS_REGS = {
    "code_version": (0x00, 4),
}
FPGA_MODULES["vers"] = (0x00, VERS_REGS)

# ADC SPI configuration
ADC_SPI_REGS = {
    "state": (0x00, 1),
    "data0": (0x02, 1),
    "data1": (0x03, 1),
}
FPGA_MODULES["adcspi"] = (0x01, ADC_SPI_REGS)

# I2C configuration (from opencores i2c module)
I2C_REGS = {
    "prer": (0x00, 2),
    "ctr": (0x02, 1),
    "txr": (0x03, 1),
    "rxr": (0x03, 1), # read-only alias of "txr"
    "cr": (0x04, 1),
    "sr": (0x04, 1), # read-only alias of "cr"
}
FPGA_MODULES["i2c"] = (0x02, I2C_REGS)

# PLL phase configuration
PP_REGS = {
    "status": (0x00, 1),
    "req_phase": (0x01, 1),
    "cur_phase": (0x02, 1),
}
FPGA_MODULES["pp"] = (0x03, PP_REGS)
