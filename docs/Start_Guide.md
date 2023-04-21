This document provides information on installing and using the
software.

This guide targets Linux machines.  The build steps and capture
software have not been tested on other platforms.

# Building the FPGA image

The MAX10 FPGA on the Haasoscope requires the Intel Quartus Software
to build the FPGA image.  (Only the free version is required.)

If the Quartus software has already been installed then one can import
the `fpga_src/qbuild/haasoscope.qpf` project file and then use the
normal build/flash steps from Quartus.

If the Quartus software is not installed then one can use
[Docker](https://en.wikipedia.org/wiki/Docker_(software)) to download
and run the Quartus software in a container.  (The installation of
Docker itself is outside the scope of this document.)  See the
[quartus.docker](../scripts/quartus.docker) file for details on
building a Quartus docker image.  Briefly:
```
docker build -t quartus -f scripts/quartus.docker
```

Once the docker image is created, one can compile the FPGA image using
the [quartus_compile.sh](../scripts/quartus_compile.sh) script:
```
./scripts/quartus_compile.sh
```

Uploading the code to the FPGA requires a "USB Blaster" device.  See
the [quartus_flash.sh](../scripts/quartus_flash.sh) script for details
on flashing.  This script may require modification to work on each
machine, but roughly one would run:
```
./scripts/quartus_flash.sh
```

Note that the above script only uploads the code to the Haasoscope
ram.  It does not modify the flash; a power cycle of the device will
return it to its previous code.

# Installing prerequisites for the capture software

The host capture software is written in Python.  It requires some
prerequisite libraries to be installed.  One can use virtualenv to
install these libraries.  One can install the virtualenv tool itself
with something like:

```
apt-get update
apt-get install virtualenv build-essentials
```

Then one can create a python environment with the libraries by running
something similar to:

```
virtualenv ~/hcap-env/
~/hcap-env/bin/pip install -r scripts/hcap-requirements.txt
```

# Running the capture software

The host capture software is invoked by running the `src/hcap.py`
tool.  For example:

```
~/hcap-env/bin/python src/hcap.py /dev/serial/by-id/usb-1a86_USB2.0-Serial-if00-port0 mydata.csv --ch0trigger '<1.0' --ch0 ac1x
```

To connect to the Haasoscope, one must select the serial device.  The
on-board full-speed USB device will show up as
`/dev/serial/by-id/usb-1a86_USB2.0-Serial-if00-port0` on many Linux
systems.

Run `~/hcap-env/bin/python src/hcap.py --help` for a list of available
command-line options.  The capturing mode of a channel can be set with
a `--ch0 dc1x` style declaration (available modes are `dc1x`, `dc10x`,
`ac1x` or `ac10x`; the default is `dc1x`).  The resulting capture data
will be stored in a csv file (`mydata.csv` in the example above).  A
trigger can be specified: `<1.0` indicates trigger on a falling
voltage below 1.0 volts (use `>v` to trigger on rising voltage level,
`~v` to trigger on any voltage above the value, or `_v` to trigger on
any voltage below the value).

# Running sigrok/pulseview

Once a capture is taken the resulting "csv" file can be analyzed in
[sigrok](https://sigrok.org/) (and its graphical interface pulseview).
For example:

```
pulseview -D -I csv:column_formats="t,4a" mydata.csv
```

Alternatively, one can run pulseview normally, select to open a
"Comma-separated values" file, open the desired csv file, and enter
`t,4a` when asked for the "Column format specs".

# Extending the duration of captures

The device can typically capture 80us of data from all four channels
at a 125Mhz capture rate.  One can reduce the amount of data captured
to extend this time range.

One can select the channels to capture using the `-c` command-line
option.  For example, `-c ch0,ch1` would only capture the first two
channels (and thus roughly double the capture time).  It is possible
to set a trigger on a channel even if the data from that channel is
not reported.

One can also reduce the query rate with the `-q` option.  For example,
`-q 25Mhz` would reduce the returned data by one fifth (and thus
typically increase the capture time by five).  If a query rate less
than 125Mhz is selected then the average of the merged measurements is
reported - this can improve the signal to noise ratio of the reported
data.

It is also possible to change the number of bits per reported
measurement using the `-b` option.  One can choose 13, 10, 8, 6, or 5
bits per measurement (the default is 8 bits).  A lower bit rate
results in more "coarse" data measurements, but can increase the
capture duration time.  The use of 13 and 10 bits is available when a
query rate less than 125Mhz is used - these bit sizes enable more
precise reporting of the averaged measurements.

Using the USB hi-speed adapter can also extend the total capture time.
If the USB interface is able to extract measurements faster than they
are recorded then one can effectively stream data from the device.

# Using the USB hi-speed adapter

One can also perform a capture using the optional USB hi-speed
adapter.  First find the device identification by running:
```
~/hcap-env/bin/python src/hcap.py -l
```

Then one can run the hcap software using that id.  For example:
```
~/hcap-env/bin/python src/hcap.py -u FT5U0000 mydata.csv --ch0trigger '<1.0' --ch0 ac1x
```
