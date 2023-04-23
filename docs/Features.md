This document contains major features and known limitations of the
code.

# Features

- Support for reading ADC measurements at up to 125Mhz on all four
  Haasoscope channels or capturing at 250Mhz on the first two
  channels.

- Either the on-board USB full-speed or the optional USB hi-speed
  adapter "hat" may be used.  The FPGA can fully saturate the hi-speed
  adapter (nominally 40MBytes per second).

- Data captures utilize the internal FPGA memory.  Data captures can
  be larger than the FPGA memory if the host capture software reads
  data sufficiently fast.  One may reduce bandwidth by selecting data
  rates slower than 125Mhz (62.50Mhz, 41.67Mhz, 31.25Mhz, 25.00Mhz,
  etc.).  The measurement bit size can also be chosen.

- Resulting data captures can be imported into Sigrok and/or
  Pulseview.

# Notable features not yet implemented

- No graphical user interface.  The current host capture software is a
  Linux command-line utility.

- The host capture software has not been optimized.  Although the FPGA
  can saturate a hi-speed USB interface, the Python based host
  software is unlikely to read the data as fast.  Also, the host
  capture software collects all capture data in memory before writing
  it to disk, which may not be optimal for large captures.

- Each Haasoscope may benefit from calibration data.  There is
  currently no calibration tool available.  Ideally there would be an
  automated tool to perform calibration.  Ideally the calibration data
  would be stored in the MAX10 FPGA on-chip flash.

- It would be useful to support flashing new FPGA images over a
  standard USB interface (and thus not require a "USB blaster" tool to
  update the image).

- There is currently no support for capturing digital measurements
  using the Haasoscope digital input pins.

# Known limitations

- The main Haasoscope software has support for some features not
  supported in this implementation:

  - No support for low-speed FPGA analog ports.

  - No support for the SSD1306 "OLED" display.

  - No support for chaining multiple Haasoscopes together (to extend
    the number of channels to 8, 12, or more).

- The host capture software has only been tested on Linux.

- The original Haasoscope software clocks the MAX19506 ADC chip at
  125Mhz.  The MAX19506 is only rated for 100Mhz.  This implementation
  also uses 125Mhz.

- Reading of each MAX19506 ADC sample requires very strict timing
  (~4ns range).  This implementation has been manually tuned to obtain
  this time range in local testing.  It is possible that different
  boards, different operating temperatures, or different compilation
  may result in incorrect timing.  (Incorrect MAX19506 ADC read timing
  may result in spurious "spikes" in reported data.)

- The Haasoscope analog frontend hardware has a complex interaction
  between its ADC, opamp, and DAC hardware.  The software has limited
  handling of the possible "gain modes" provided by the hardware.
