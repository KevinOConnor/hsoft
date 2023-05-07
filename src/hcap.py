#!/usr/bin/env python
# Interact with Haasoscope fpga code
#
# Copyright (C) 2023  Kevin O'Connor <kevin@koconnor.net>
#
# This file may be distributed under the terms of the GNU GPLv3 license.
import sys, optparse, time, io
import fpgaregs

class error(Exception):
    pass


######################################################################
# Message rx/tx handling
######################################################################

REQ_HDR=0x52
SCAN_CHAR=0x7e

def crc16_ccitt(buf, start, end):
    crc = 0xffff
    for pos in range(start, end):
        data = buf[pos]
        data ^= crc & 0xff
        data ^= (data & 0x0f) << 4
        crc = ((data << 8) | (crc >> 8)) ^ (data >> 4) ^ (data << 3)
    return [crc >> 8, crc & 0xff]

class SerialHandler:
    def __init__(self, modregs):
        self.modregs = modregs
        self.ser = None
        # Message parsing
        self.tx_seq = self.rx_seq = 0
        self.no_seq_warnings = False
        self.need_scan = False
        self.read_finish = 0.
        self.data = bytearray()
        self.bulk_read_mode = False
        # Callbacks
        self.handlers = {}
        # Command tracking
        self.cmd = self.cmd_result = None
    def register_stream(self, strm_id, callback):
        if callback is None:
            del self.handlers[strm_id]
            return
        self.handlers[strm_id] = callback
    def set_bulk_mode(self, bulk_read_mode):
        self.bulk_read_mode = bulk_read_mode
    def _warn(self, msg):
        sys.stdout.write("WARN: %s\n" % (msg,))
    def _default_stream(self, msg):
        self._warn("Message (size %d) with unknown stream id" % (len(msg),))
    def _flush_connection(self):
        self.ser.write(bytes(bytearray([0x00] * 15 + [SCAN_CHAR])))
    def clear(self):
        self._flush_connection()
        self.cmd = self.cmd_result = None
    def read_data(self, read_finish):
        self.read_finish = read_finish
        bulk_read_mode = self.bulk_read_mode
        reads = []
        reads_pos = 0
        data = self.data
        dpos = 0
        need_bytes = 6
        while 1:
            if len(data) - dpos < need_bytes:
                if len(reads) > reads_pos:
                    data.extend(reads[reads_pos])
                    reads_pos += 1
                    continue
                if reads_pos:
                    reads[:] = []
                    reads_pos = 0
                if dpos:
                    data[:dpos] = []
                    dpos = 0
                curtime = time.time()
                if curtime >= self.read_finish:
                    return
                # Read data
                retry_read = False
                while 1:
                    d = self.ser.read(16 * 1024)
                    if d:
                        reads.append(d)
                        if not self.bulk_read_mode:
                            break
                        retry_read = True
                        continue
                    if not retry_read:
                        break
                    retry_read = False
                continue
            if self.need_scan:
                drop = len(data)
                sc = data.find(SCAN_CHAR)
                if sc >= 0:
                    drop = sc + 1
                    self.need_scan = False
                self._warn("Discard %d bytes" % (drop,))
                dpos += drop
                continue
            msg_header = data[dpos]
            msg_lenseq = data[dpos+1] | (data[dpos+2] << 8)
            msg_datalen = msg_lenseq >> 6
            need_bytes = msg_datalen + 6
            if msg_header & 0xf0 == 0x60:
                if len(data) - dpos < need_bytes:
                    # Need more data
                    continue
                msg_crc = list(data[dpos+msg_datalen+3:dpos+msg_datalen+5])
                msg_seq = msg_lenseq & 0x3f
                msg_term = data[dpos+msg_datalen+5]
                if (msg_term == SCAN_CHAR
                    and crc16_ccitt(data, dpos, dpos+msg_datalen+3) == msg_crc):
                    # Got valid response
                    if msg_seq != (self.rx_seq + 1) & 0x3f:
                        if not self.no_seq_warnings:
                            self._warn("Receive sequence mismatch (%d vs %d)"
                                       % (msg_seq, self.rx_seq))
                    self.rx_seq = msg_seq
                    msg_data = data[dpos+3:dpos+msg_datalen+3]
                    dpos += need_bytes
                    need_bytes = 6
                    # Process data in callback
                    hdlr = self.handlers.get(msg_header, self._default_stream)
                    hdlr(msg_data)
                    continue
            # Invalid data - rescan
            need_bytes = 6
            self.need_scan = True
    def _build_message(self, tx_seq, is_write, addr, val):
        msg = [REQ_HDR, tx_seq & 0x3f, 0x01,
               is_write, addr & 0xff, (addr >> 8) & 0xff, val & 0xff]
        msg.extend(crc16_ccitt(msg, 0, len(msg)) + [SCAN_CHAR])
        return bytes(bytearray(msg))
    def _handle_response(self, msgdata):
        # Got response to request
        if len(msgdata) != 2:
            self._warn("Unexpected response length %d" % (len(msgdata),))
            return
        errseq = msgdata[0]
        res = msgdata[1]
        self.tx_seq = errseq & 0x3f
        err = errseq & 0x80
        if self.cmd is None:
            self._warn("Unexpected message response (seq %d)"
                       % (self.tx_seq,))
            return
        if err:
            # Sequence number mismatch
            if not self.no_seq_warnings:
                self._warn("Send sequence mismatch (seq %d vs %d)"
                           % (self.tx_seq, self.cmd[0]))
            self.cmd = (self.tx_seq,) + self.cmd[1:]
            msg = self._build_message(*self.cmd)
            self.ser.write(msg)
            return
        if self.tx_seq != (self.cmd[0] + 1) & 0x3f:
            if not self.no_seq_warnings:
                self._warn("Response to unknown query (seq %d vs %d)"
                           % (self.tx_seq, self.cmd[0]))
            return
        # A valid response
        self.cmd_result = res
        self.cmd = None
        self.read_finish = 0.
    def _tx_message(self, is_write, addr, val):
        if self.cmd is not None:
            raise error("Can't send command while in command")
        self.cmd = (self.tx_seq, is_write, addr, val)
        msg = self._build_message(*self.cmd)
        self.ser.write(msg)
        #sys.stdout.write("raw write: %s\n" % (repr(msg),))
        start_time = time.time()
        retry_time = start_time + 0.250
        while 1:
            self.read_data(retry_time)
            if self.cmd is None:
                return self.cmd_result
            self._warn("Timeout in message handler. Retrying.")
            self._flush_connection()
            self.ser.write(msg)
            curtime = time.time()
            retry_time = curtime + 0.250
    def write_reg(self, modname, regname, val):
        #sys.stdout.write("Send: write 0x%04x of 0x%04x\n" % (addr, val))
        modaddr, regs = self.modregs[modname]
        regaddr, regsize = regs[regname]
        addr = (modaddr << 8) | regaddr
        if regsize == 4:
            self._tx_message(0x80, addr, val & 0xff)
            self._tx_message(0x80, addr + 1, (val >> 8) & 0xff)
            self._tx_message(0x80, addr + 2, (val >> 16) & 0xff)
            self._tx_message(0x80, addr + 3, (val >> 24) & 0xff)
        elif regsize == 2:
            self._tx_message(0x80, addr, val & 0xff)
            self._tx_message(0x80, addr + 1, (val >> 8) & 0xff)
        else:
            self._tx_message(0x80, addr, val & 0xff)
    def read_reg(self, modname, regname):
        #sys.stdout.write("Send: read 0x%04x\n" % (addr,))
        modaddr, regs = self.modregs[modname]
        regaddr, regsize = regs[regname]
        addr = (modaddr << 8) | regaddr
        if regsize == 4:
            return (self._tx_message(0x00, addr, 0x00)
                    | (self._tx_message(0x00, addr + 1, 0x00) << 8)
                    | (self._tx_message(0x00, addr + 2, 0x00) << 16)
                    | (self._tx_message(0x00, addr + 3, 0x00) << 24))
        elif regsize == 2:
            return (self._tx_message(0x00, addr, 0x00)
                    | (self._tx_message(0x00, addr + 1, 0x00) << 8))
        else:
            return self._tx_message(0x00, addr, 0x00)
    def dump_registers(self, modname=None):
        if modname is None:
            all_mods = self.modregs.items()
            all_mods = sorted([(adr, mn) for mn, (adr, regs) in all_mods])
            for adr, modname in all_mods:
                self.dump_registers(modname)
            return
        adr, regs = self.modregs[modname]
        regs = [(radr, rn) for rn, (radr, rs) in regs.items()]
        for radr, regname in sorted(regs):
            v = self.read_reg(modname, regname)
            sys.stdout.write("%s: %s: 0x%02x\n" % (modname, regname, v))
    def setup(self, ser):
        self.ser = ser
        self.register_stream(0x60, self._handle_response)
        # Verify connection and obtain initial sequence numbers
        self._flush_connection()
        self.no_seq_warnings = True
        vers = self.read_reg("vers", "code_version")
        self.no_seq_warnings = False
        sys.stdout.write("FPGA code version: %d.%d.%d\n"
                         % (vers >> 16, (vers >> 8) & 0xff, vers & 0xff))


######################################################################
# I2C helper
######################################################################

class i2c_error(Exception):
    pass

class I2CHelper:
    def __init__(self, serialhdl):
        self.read_reg = serialhdl.read_reg
        self.write_reg = serialhdl.write_reg
    def _send_i2c_byte(self, cmdflags, data=None):
        if not (cmdflags & (1<<5)):
            self.write_reg("i2c", "txr", data)
        self.write_reg("i2c", "cr", cmdflags)
        while 1:
            res = self.read_reg("i2c", "sr")
            if not (res & (1<<1)):
                # Complete
                break
        expected_res = (cmdflags & (1<<6)) ^ (1<<6)
        if (res & ~(0x01)) != expected_res:
            if expected_res:
                self.write_reg("i2c", "cr", 1<<6)
            raise i2c_error("i2c send fault")
    def _try_send_i2c(self, addr, write, read_count=0):
        addrwr = addr << 1
        if write:
            self._send_i2c_byte((1<<7) | (1<<4), addrwr)
            for i, b in enumerate(write):
                cmdflags = 1<<4
                if not read_count and i == len(write) - 1:
                    cmdflags |= 1<<6
                self._send_i2c_byte(cmdflags, b)
        res = []
        if read_count:
            self._send_i2c_byte((1<<7) | (1<<4), addrwr | 1)
            for i in range(read_count):
                cmdflags = 1<<5
                if i == read_count - 1:
                    cmdflags |= (1<<6) | (1<<3)
                self._send_i2c_byte(cmdflags)
                res.append(self.read_reg("i2c", "rxr"))
        #sys.stdout.write("i2c 0x%02x %s is %s\n" % (addr, write, res))
        return res
    def send_i2c(self, addr, write, read_count=0):
        while 1:
            try:
                return self._try_send_i2c(addr, write, read_count)
            except i2c_error as e:
                sys.stdout.write("i2c send fail to addr %02x\n" % (addr,))
                time.sleep(0.001)
    def setup(self, fpga_freq):
        i2c_freq = 100000
        self.write_reg("i2c", "ctr", 0x00)
        isp = fpga_freq // (5 * i2c_freq) - 1
        self.write_reg("i2c", "prer", isp)
        self.write_reg("i2c", "ctr", 0x80)


######################################################################
# Chip helpers
######################################################################

# IO expander helper
class mcp23017:
    def __init__(self, send_i2c, i2c_addr, pin_names):
        self.send_i2c = send_i2c
        self.i2c_addr = i2c_addr
        self.pin_names = pin_names
        self.reg_iodir = 0xffff
        self.reg_gppu = self.reg_iolat = self.reg_gpio = 0
    def update_pins(self):
        addr = self.i2c_addr
        iodir = self.reg_iodir
        iolat = self.reg_iolat
        gppu = self.reg_gppu
        self.send_i2c(addr, [0x14, iolat & 0xff, iolat >> 8])
        self.send_i2c(addr, [0x00, iodir & 0xff, iodir >> 8])
        self.send_i2c(addr, [0x0c, gppu & 0xff, gppu >> 8])
    def read_pins(self):
        res = self.send_i2c(self.i2c_addr, [0x12], read_count=2)
        self.reg_gpio = res[0] | (res[1] << 8)
    def set_output(self, pin_name, value):
        bit = 1 << self.pin_names[pin_name]
        self.reg_iodir = self.reg_iodir & ~bit
        self.reg_iolat = (self.reg_iolat & ~bit) | (bit if value else 0)
    def set_input(self, pin_name, pullup=0):
        bit = 1 << self.pin_names[pin_name]
        self.reg_iodir = self.reg_iodir | bit
        self.reg_gppu = (self.reg_gppu & ~bit) | (bit if pullup else 0)
    def get_input(self, pin_name):
        bit = 1 << self.pin_names[pin_name]
        return not not (self.reg_gpio & bit)
    def dump_pins(self):
        for pin, pin_name in sorted((b, n) for n, b in self.pin_names.items()):
            bit = 1 << pin
            v = self.reg_iolat
            d = "output"
            if self.reg_iodir & bit:
                v = self.reg_gpio
                d = "input"
            print("%s: %s %d" % (pin_name, d, not not (v & bit)))

# DAC helper
class mcp4728:
    def __init__(self, send_i2c, i2c_addr):
        self.send_i2c = send_i2c
        self.i2c_addr = i2c_addr
    def _encode_volt(self, volt):
        volt = max(0., min(3.3, volt))
        if volt >= 2.0485:
            return max(0, min(0xfff, int(round(4096 * volt / 4.096)))) | (1<<12)
        return max(0, min(0xfff, int(round(4096 * volt / 2.048))))
    def _decode_volt(self, value):
        if value & (1<<12):
            return float(value & 0xfff) / 4096 * 4.096
        return float(value & 0xfff) / 4096 * 2.048
    def calc_volt(self, volt):
        return self._decode_volt(self._encode_volt(volt))
    def set_dac(self, channel, volt):
        value = self._encode_volt(volt)
        #sys.stdout.write("dac %d %.4f 0x%03x\n" % (channel, volt, value))
        self.send_i2c(self.i2c_addr,
                      [0x40 | (channel << 1), ((value >> 8) & 0x1f) | 0x80,
                       value & 0xff])

# max19506 SPI helper
class Max19506spi:
    def __init__(self, serialhdl):
        self.read_reg = serialhdl.read_reg
        self.write_reg = serialhdl.write_reg
    def wait_spi_ready(self):
        while 1:
            res = self.read_reg("adcspi", "state")
            if not res:
                break
    def send_spi(self, reg, val):
        self.wait_spi_ready()
        self.write_reg("adcspi", "data0", reg & 0x7f)
        self.write_reg("adcspi", "data1", val & 0xff)
        self.write_reg("adcspi", "state", 0x01)
        self.wait_spi_ready()
    def setup(self):
        # configure MAX19506 ADC
        self.send_spi(0x01, 0x00) # Default non-multiplexed output
        self.send_spi(0x02, 0x03) # Disable DOR and DCLK output
        self.send_spi(0x03, 0b10111111) # Use "-3T/16" data output timing
        self.send_spi(0x04, 0x00) # Default 50 Ohm on ChA data pins
        self.send_spi(0x05, 0x00) # Default 50 Ohm on ChB data pins
        self.send_spi(0x06, 0x10) # "offset binary" output
        self.send_spi(0x08, 0x00) # Default voltage modes (0.9V)

# Set the PLL phase of the extadc2 clock
class PLLPhase:
    def __init__(self, serialhdl):
        self.read_reg = serialhdl.read_reg
        self.write_reg = serialhdl.write_reg
    def wait_phase_ready(self):
        while 1:
            res = self.read_reg("pp", "status")
            if not res:
                break
    def setup(self, is_interleaving):
        targetphase_ps = 0
        if is_interleaving:
            targetphase_ps = 4000 # four nanoseconds
        phasestep_ps = 100
        targetphase = targetphase_ps // phasestep_ps
        rp = self.read_reg("pp", "req_phase")
        if rp == targetphase:
            return
        sys.stdout.write("Setting extadc2 clock phase\n")
        self.wait_phase_ready()
        self.write_reg("pp", "req_phase", targetphase)
        self.wait_phase_ready()


######################################################################
# Sample Queue handling
######################################################################

# Mapping of bit resolution to fpga control code
DEPOSIT_TYPES = {
    # num_bits: (measurements_per_sample, shift, code)
    8: (4, 8, 0), 10: (3, 10, 1), 13: (2, 13, 2),
    5: (6, 5, 3), 6: (5, 13, 6),
}

class SQHelper:
    def __init__(self, serialhdl, fpga_freq):
        self.serialhdl = serialhdl
        self.fpga_freq = fpga_freq
        self.read_reg = self.serialhdl.read_reg
        self.write_reg = self.serialhdl.write_reg
        # Frame config
        self.frame_preface = 0.000002
        self.frame_time = 0.100
        self.channel_div = 1
        self.query_rate = fpga_freq
        # Handling of measurements within each sample queue entry
        self.interleave = False
        self.meas_bits = 8
        self.meas_mask = 0xff
        self.meas_base = 0
        self.do_meas_sum = True
        # Frame handling
        self.frame_datas = []
        self.af_helpers = None
        self.csvfilename = None
    def setup_cmdline_options(self, opts):
        opts.add_option("-q", "--queryrate", type="string", default="125MHz",
                        help="Sample query rate")
        opts.add_option("-b", "--bits", type=int, default=8,
                        help="Number of bits per measurement")
        opts.add_option("--duration", type="string", default="100ms",
                        help="Duration of data to report")
        opts.add_option("--preface", type="string", default="2us",
                        help="Time prior to trigger to report")
        opts.add_option("--average", type="int", default=1,
                        help="Average measurements at lower query rates")
    def _parse_hz(self, val):
        val = val.strip().lower()
        mult = 1000000.
        for s, m in [("mhz", 1000000.), ("khz", 1000.), ("hz", 1.)]:
            if val.endswith(s):
                val = val[:-len(s)].strip()
                mult = m
                break
        return float(val) * mult
    def _parse_time(self, val):
        val = val.strip().lower()
        mult = 1.
        for s, m in [("us", .000001), ("ms", .001), ("s", 1.)]:
            if val.endswith(s):
                val = val[:-len(s)].strip()
                mult = m
                break
        return float(val) * mult
    def note_cmdline_options(self, options):
        qrate = self._parse_hz(options.queryrate)
        if qrate == 250000000.:
            self.interleave = True
            qrate /= 2.
        meas_bits = options.bits
        if meas_bits not in DEPOSIT_TYPES:
            sys.stdout.write("Available bit modes: %s\n"
                             % (sorted(DEPOSIT_TYPES.keys()),))
            sys.exit(-1)
        self.meas_bits = meas_bits
        self.do_meas_sum = not not options.average
        self.channel_div = max(1, min(0x100, int(self.fpga_freq // qrate)))
        self.frame_time = self._parse_time(options.duration)
        self.preface_time = self._parse_time(options.preface)
    def note_filename(self, csvfilename):
        self.csvfilename = csvfilename
    def _note_frame_data(self, msgdata):
        self.frame_datas.append(msgdata)
    def is_interleaving(self):
        return self.interleave
    def get_status(self):
        return ("Hz=%.0f interleave=%d preface=%.6fs duration=%.6f\n"
                "  meas_sum=%d meas_bits=%d meas_mask=%x meas_base=%d\n"
                % (self.fpga_freq / self.channel_div, self.interleave,
                   self.preface_time, self.frame_time,
                   self.do_meas_sum, self.meas_bits,
                   self.meas_mask, self.meas_base))
    def _parse_frame_data(self, frame_slot):
        # Map active channels
        interleave = self.interleave
        cmap = []
        hdr_desc = []
        num_channels = 0
        for ch, ah in enumerate(self.af_helpers):
            hdr = "unused%d" % (ch,)
            if ah.check_is_capturing():
                cmap.append((ah, ch, num_channels * 4))
                num_channels += 1
                if not interleave or ch < 2:
                    hdr = "ch%d" % (ch,)
            hdr_desc.append(hdr)
        # Handle multiple measurements in each sample queue entry
        meas_per_sample, meas_shift, meas_code = DEPOSIT_TYPES[self.meas_bits]
        meas_mask = self.meas_mask
        meas_mult = 1.
        if self.do_meas_sum:
            meas_mult = 1. / self.channel_div
        # Skip unaligned reports at start and end of data
        frame_datas = self.frame_datas
        total_bytes = sum([len(fd) for fd in frame_datas])
        sample_count = total_bytes // 4
        skip_start = (num_channels - (frame_slot % num_channels)) % num_channels
        sample_count -= skip_start
        sample_count -= sample_count % num_channels
        stime = float(self.channel_div) / self.fpga_freq
        if interleave:
            stime /= 2.
        total_sample_groups = sample_count // num_channels
        total_lines = total_sample_groups * meas_per_sample
        sys.stdout.write("Total bytes %d (%d sample queue) %d lines (%.9fs)\n"
                         % (total_bytes, total_bytes//4,
                            total_lines, total_lines * stime))
        # CSV file header
        hdrs = ["; HSoft data capture '%s'" % (time.asctime(),)]
        hdrs.append(";")
        sts = self.get_status()
        hdrs.extend([("; " + s).strip() for s in sts.split('\n')])
        for ah in self.af_helpers:
            sts = ah.get_status()
            hdrs.extend([("; " + s).strip() for s in sts.split('\n')])
        hdrs.append("time,%s" % (",".join(hdr_desc)))
        hdrs.append("")
        header = "\n".join(hdrs)
        # Create file
        csvf = io.open(self.csvfilename, "w")
        csvf.write(header)
        # Write data to file
        frame_data = bytearray()
        frames_pos = 0
        line_data = [[0.] * 4 for i in range(meas_per_sample)]
        line_num = sample_group_num = 0
        base_pos = skip_start * 4
        while sample_group_num < total_sample_groups:
            # Check if need to extract more data
            if len(frame_data) < base_pos + 4 * num_channels:
                if base_pos and len(frame_data) > base_pos:
                    frame_data[:base_pos] = []
                    base_pos = 0
                frame_data.extend(frame_datas[frames_pos])
                frames_pos += 1
                continue
            # Find measurements for this "group" of data
            for ah, ch, offset in cmap:
                spos = base_pos + offset
                d = (frame_data[spos] | (frame_data[spos+1] << 8)
                     | (frame_data[spos+2] << 16) | (frame_data[spos+3] << 24))
                d = d | (d << 32)
                for j in range(meas_per_sample):
                    m = (d >> ((j * meas_shift) & 0x1f)) & meas_mask
                    v = ah.calc_probe_volt(m * meas_mult)
                    line_data[meas_per_sample - 1 - j][ch] = v
            sample_group_num += 1
            base_pos += 4 * num_channels
            # Write line to csv file
            if interleave:
                for ld in line_data:
                    csvf.write("%.9f,%.6f,%.6f,0,0\n%.9f,%.6f,%.6f,0,0\n"
                               % (line_num*stime, ld[0], ld[1],
                                  (line_num+1)*stime, ld[2], ld[3]))
                    line_num += 2
            else:
                for ld in line_data:
                    csvf.write("%.9f,%.6f,%.6f,%.6f,%.6f\n"
                               % (line_num*stime, ld[0], ld[1], ld[2], ld[3]))
                    line_num += 1
        csvf.write("; End of capture (%d data lines)\n" % (line_num,))
        csvf.close()
    def _calc_meas_mask(self):
        meas_bits = self.meas_bits
        if self.channel_div == 1:
            meas_bits = self.meas_bits = min(8, meas_bits)
        meas_mask = (1 << meas_bits) - 1
        meas_base = 0
        max_val = 0xff
        if self.do_meas_sum:
            max_val *= self.channel_div
        max_val_num_bits = max_val.bit_length()
        if max_val_num_bits > meas_bits:
            need_shift = max_val_num_bits - meas_bits
            meas_mask <<= need_shift
            meas_base = 1 << (need_shift - 1)
        self.meas_mask = meas_mask
        self.meas_base = meas_base
    def capture_frame(self, af_helpers, force_trigger):
        self.af_helpers = af_helpers
        self._calc_meas_mask()
        sys.stdout.write(self.get_status())
        # Enable fifo
        meas_per_sample, meas_shift, meas_code = DEPOSIT_TYPES[self.meas_bits]
        num_channels = 0
        for ch in range(4):
            is_capturing = self.af_helpers[ch].check_is_capturing()
            num_channels += is_capturing
            chname = "ch%d" % (ch,)
            self.write_reg(chname, "status", 0x00)
            self.write_reg(chname, "acc_cnt", self.channel_div - 1)
            self.write_reg(chname, "sum_mask", self.meas_mask)
            self.write_reg(chname, "initial_sum", self.meas_base)
            self.write_reg(chname, "status",
                           (is_capturing | (self.do_meas_sum << 1)
                            | (meas_code << 4)))
        qrate = (self.fpga_freq * num_channels
                 / (meas_per_sample * self.channel_div))
        frame_size = max(16, min(0xffffffff, int(self.frame_time * qrate)))
        self.write_reg("sq", "frame_size", frame_size)
        frame_prefix = max(8, min(0x1f00, int(self.preface_time * qrate)))
        self.write_reg("sq", "frame_preface", frame_prefix)
        # Start sampling
        sys.stdout.write(" START SAMPLING\n")
        self.write_reg("sq", "status", 0x81)
        start_pos = self.read_reg("sq", "reg_fifo_position")
        # Query fifo data
        self.serialhdl.register_stream(0x61, self._note_frame_data)
        self.serialhdl.read_data(time.time() + 0.020)
        self.serialhdl.set_bulk_mode(True)
        sys.stdout.write(" START CAPTURE\n")
        start_time = time.time()
        if force_trigger:
            self.write_reg("sq", "status", 0x07)
        else:
            self.write_reg("sq", "status", 0x03)
        for i in range(3000):
            self.serialhdl.read_data(start_time + (i + 1) * 0.010)
            sts = self.read_reg("sq", "status")
            if sts & 0x0a == 0x00:
                if sts & 0x01:
                    sys.stdout.write(" CAPTURE COMPLETE\n")
                else:
                    end_time = time.time()
                    sys.stdout.write(" CAPTURE EARLY END (t=%.3f)\n"
                                     % (end_time - start_time))
                break
        frame_pos = self.read_reg("sq", "reg_fifo_position")
        sys.stdout.write(" FINALIZE CAPTURE\n")
        self.serialhdl.set_bulk_mode(False)
        self.write_reg("sq", "status", 0x00)
        frame_diff = frame_pos - start_pos - frame_prefix - 1
        frame_slot = frame_diff & 0xffffffff
        self._parse_frame_data(frame_slot)
    def setup(self):
        self.write_reg("sq", "status", 0x00)


######################################################################
# Analog frontend helper
######################################################################

# XXX - the following is from experiments on one Haasoscope.  Other
# scopes will likely benefit from other values.  Ideally this would be
# stored in FPGA flash on the Haasoscope.  This info should be
# per-channel.
ADC_GAIN1_FACTOR=-1.5 * 1100000. / (200000. * 255.)
ADC_GAIN10_FACTOR=-1.5 * 1100000. / (2000000. * 255.)
BASE_PROBES = {
    'ac1x': {'dac': 1.235, 'adc_factor': ADC_GAIN1_FACTOR},
    'ac10x': {'dac': 2.35, 'adc_factor': ADC_GAIN10_FACTOR},
    'dc1x': {'dac': 1.0575, 'adc_factor': ADC_GAIN1_FACTOR},
    'dc10x': {'dac': 1.5535, 'adc_factor': ADC_GAIN10_FACTOR},
}
PROBES = {
    ('dc1x', '10x'): {'dac': 1.2125, 'adc_factor': ADC_GAIN1_FACTOR * 10.},
    ('dc10x', '10x'): {'dac': 2.329, 'adc_factor': ADC_GAIN10_FACTOR * 10.},
}

# Haasoscope analog frontend configuration helper
class AFHelper:
    def __init__(self, serialhdl, dac, ioexp1, channel, interleave_channel):
        self.serialhdl = serialhdl
        self.dac = dac
        self.ioexp1 = ioexp1
        self.channel = channel
        self.interleave_channel = interleave_channel
        self.interleave = False
        self.sw_imp10Mohm = self.sw_gain100 = False
        self.ac_isolate = self.is_gain10 = False
        self.dac_v = self.base_adc = self.base_v = self.adc_factor = 0.
        self.trigger_code = 0
        self.trigger_volt = 0.
        self.is_capturing = False
    def setup_cmdline_options(self, opts):
        if self.channel == 0:
            opts.add_option("-c", "--channels", type="string",
                            default="ch0,ch1,ch2,ch3",
                            help="Channels to capture")
        prefix = "--ch%d" % (self.channel,)
        help_prefix = "Channel %d " % (self.channel,)
        opts.add_option(prefix, type="string", default="dc1x",
                        help=help_prefix + "mode")
        opts.add_option(prefix + "probe", type="string", default=None,
                        help=help_prefix + "probe type")
        opts.add_option(prefix + "trigger", type="string", default=None,
                        help=help_prefix + "set trigger")
    def _parse_channels(self, val):
        channels = []
        for p in val.lower().split(','):
            p = p.strip()
            if p.startswith("ch"):
                p = p[2:]
            channels.append(int(p))
        return channels
    def _parse_channel_mode(self, val):
        val = val.strip().lower()
        modes = {"dc1x": (False, False), "dc10x": (False, True),
                 "ac1x": (True, False), "ac10x": (True, True)}
        if val not in modes:
            sys.stdout.write("Available modes: DC1x, DC10x, AC1x, AC10x\n")
            sys.exit(-1)
        return modes[val]
    def _parse_probe_type(self, probe_desc, mode_desc):
        base_info = BASE_PROBES.get(mode_desc)
        if probe_desc is not None:
            probe_desc = probe_desc.lower().strip()
            info = PROBES.get((mode_desc, probe_desc))
            if info is None and mode_desc.startswith('ac'):
                info = PROBES.get(('dc' + mode_desc[2:], probe_desc))
        else:
            info = base_info
        if info is None:
            modes = [k[1] for k in PROBES.keys() if k[0] == mode_desc]
            sys.stdout.write("Unknown probe '%s' - available: %s\n"
                             % (probe_desc, ", ".join(modes)))
            sys.exit(-1)
        self.adc_factor = info['adc_factor']
        if self.ac_isolate and base_info is not None:
            # Only use adc_factor in ac_isolate mode
            info = base_info
        self.dac_v = info['dac']
        self.base_adc = info.get('adc', 255. / 2.)
        self.base_v = info.get('voltage', 0.)
    def _parse_trigger(self, val):
        val = val.strip()
        tcode = 0x04
        for s, c in [("<", 0x04), (">", 0x06), ("_", 0x00), ("~", 0x02)]:
            if val.startswith(s):
                val = val[1:].strip()
                tcode = c
                break
        tvolt = float(val)
        return tcode | 0x01, tvolt
    def note_cmdline_options(self, options):
        channel = self.channel
        if self.interleave:
            channel = self.interleave_channel
        channels_desc = getattr(options, "channels")
        channels = self._parse_channels(channels_desc)
        self.is_capturing = (channel in channels)
        prefix = "ch%d" % (channel,)
        mode_desc = getattr(options, prefix)
        self.ac_isolate, self.is_gain10 = self._parse_channel_mode(mode_desc)
        probe_desc = getattr(options, prefix + "probe")
        self._parse_probe_type(probe_desc, mode_desc)
        tdesc = getattr(options, prefix + "trigger")
        if tdesc is not None:
            self.trigger_code, self.trigger_volt = self._parse_trigger(tdesc)
    def note_switches(self, sw_imp10Mohm, sw_gain100):
        self.sw_imp10Mohm = sw_imp10Mohm
        self.sw_gain100 = sw_gain100
    def note_interleaving(self, is_interleaving):
        self.interleave = is_interleaving
    def have_trigger(self):
        return self.trigger_code != 0
    def check_is_capturing(self):
        return self.is_capturing
    def _calc_adc(self, probe_v):
        adc_result = (probe_v - self.base_v) / self.adc_factor + self.base_adc
        return max(0, min(255, int(adc_result + 0.5)))
    def calc_probe_volt(self, adc_result):
        probe_v = self.base_v + (adc_result - self.base_adc) * self.adc_factor
        return probe_v
    def get_status(self):
        trig = "None"
        if self.trigger_code:
            trigtype = {0x04: "falling", 0x06: "rising",
                        0x00: "below", 0x02: "above"}
            ttype = trigtype[self.trigger_code & ~0x01]
            tvolt = self.calc_probe_volt(self._calc_adc(self.trigger_volt))
            trig = "%s %.6fV" % (ttype, tvolt)
        min_v = self.calc_probe_volt(255)
        max_v = self.calc_probe_volt(0)
        return ("channel%d: capturing=%d ac_isolate=%d"
                " 50ohm=%d gain10x=%d gain100x=%d\n"
                "  DAC=%.4fV base_adc=%.6f base_v=%.6fV adc_factor=%.6fV\n"
                "  range=%.6fV:%.6fV trigger: %s\n"
                % (self.channel, self.is_capturing, self.ac_isolate,
                   not self.sw_imp10Mohm, self.is_gain10, self.sw_gain100,
                   self.dac_v, self.base_adc, self.base_v, self.adc_factor,
                   min_v, max_v, trig))
    def setup_channel(self):
        if not self.sw_imp10Mohm or self.sw_gain100:
            sys.stdout.write("WARN: 100x mode and 50ohm mode not supported\n")
        # Configure channel settings
        suffix = "_ch%d" % (self.channel,)
        dc_connect = is_gain10 = False
        dac_v = 0.
        is_active = self.is_capturing or self.trigger_code
        if self.interleave and self.interleave_channel != self.channel:
            is_active = False
        if is_active:
            dc_connect = not self.ac_isolate
            is_gain10 = self.is_gain10
            dac_v = self.dac_v
        self.ioexp1.set_output("dc_connect" + suffix, dc_connect)
        self.ioexp1.set_output("gain" + suffix, is_gain10)
        self.dac.set_dac(self.channel, dac_v)
        # Setup trigger
        modname = "ch%d" % (self.channel,)
        self.serialhdl.write_reg(modname, "trigger", 0x00)
        if self.trigger_code:
            tadc = self._calc_adc(self.trigger_volt)
            self.serialhdl.write_reg(modname, "thresh", tadc)
            self.serialhdl.write_reg(modname, "trigger", self.trigger_code)
        # Report config
        sys.stdout.write(self.get_status())


######################################################################
# Haasoscope handling
######################################################################

FPGA_FREQ=125000000
FPGA_SLOW_FREQ=62500000
BAUD=1500000

I2C_DAC_ADDR=0x60
I2C_EXP1_ADDR=0x20
I2C_EXP2_ADDR=0x21

PINS_IOEXP1 = {
    "gain_ch0": 0, "gain_ch1": 1, "gain_ch2": 2, "gain_ch3": 3,
    "enable_ch2": 4, "enable_ch3": 5,
    "dc_connect_ch0": 8, "dc_connect_ch1": 9,
    "dc_connect_ch2": 10, "dc_connect_ch3": 11,
    "shutdown_adc1": 12, "shutdown_adc2": 13
}
PINS_IOEXP2 = {
    "led0": 0, "led1": 1, "led2": 2, "led3": 3,
    "extra_io1": 4, "extra_io2": 5, "extra_io3": 6, "extra_io4": 7,
    "switch_imp10Mohm_ch0": 8, "switch_imp10Mohm_ch1": 9,
    "switch_imp10Mohm_ch2": 10, "switch_imp10Mohm_ch3": 11,
    "switch_gain100_ch0": 12, "switch_gain100_ch1": 13,
    "switch_gain100_ch2": 14, "switch_gain100_ch3": 15
}

class HProcessor:
    def __init__(self):
        self.serialhdl = SerialHandler(fpgaregs.FPGA_MODULES)
        self.sqhelper = SQHelper(self.serialhdl, FPGA_FREQ)
        self.adcspi = Max19506spi(self.serialhdl)
        self.i2c = i2c = I2CHelper(self.serialhdl)
        self.dac = mcp4728(i2c.send_i2c, I2C_DAC_ADDR)
        self.pllphase = PLLPhase(self.serialhdl)
        # gpio expanders
        self.ioexp1 = mcp23017(i2c.send_i2c, I2C_EXP1_ADDR, PINS_IOEXP1)
        self.ioexp2 = mcp23017(i2c.send_i2c, I2C_EXP2_ADDR, PINS_IOEXP2)
        pin_to_ioexp = {n: self.ioexp1 for n in PINS_IOEXP1}
        pin_to_ioexp.update({n: self.ioexp2 for n in PINS_IOEXP2})
        for pin_name, ioexp in pin_to_ioexp.items():
            if pin_name.startswith("switch_"):
                ioexp.set_input(pin_name, 1)
            elif pin_name.startswith("extra_io"):
                ioexp.set_input(pin_name)
            else:
                ioexp.set_output(pin_name, 0)
        # analog frontend helpers
        self.af_helpers = [AFHelper(self.serialhdl, self.dac, self.ioexp1,
                                    ch, ch % 2) for ch in range(4)]
    def setup_cmdline_options(self, opts):
        self.sqhelper.setup_cmdline_options(opts)
        for afh in self.af_helpers:
            afh.setup_cmdline_options(opts)
    def note_cmdline_options(self, options, args):
        self.sqhelper.note_cmdline_options(options)
        for afh in self.af_helpers:
            afh.note_interleaving(self.sqhelper.is_interleaving())
            afh.note_cmdline_options(options)
    def note_filename(self, csvfilename):
        self.sqhelper.note_filename(csvfilename)
    def run(self, ser):
        self.serialhdl.setup(ser)
        self.sqhelper.setup()
        self.adcspi.setup()
        self.i2c.setup(FPGA_SLOW_FREQ)
        self.pllphase.setup(self.sqhelper.is_interleaving())
        # configure mcp23017 gpio expander 2
        self.ioexp2.set_output("led0", 1)
        self.ioexp2.update_pins()
        self.ioexp2.read_pins()
        self.ioexp2.dump_pins()
        # Setup channels
        interleave = self.sqhelper.is_interleaving()
        self.ioexp1.set_output("enable_ch2", not interleave)
        self.ioexp1.set_output("enable_ch3", not interleave)
        force_trigger = True
        for ch in range(4):
            ah = self.af_helpers[ch]
            suffix = "_ch%d" % (ch,)
            sw_imp10Mohm = self.ioexp2.get_input("switch_imp10Mohm" + suffix)
            sw_gain100 = self.ioexp2.get_input("switch_gain100" + suffix)
            ah.note_switches(sw_imp10Mohm, sw_gain100)
            ah.setup_channel()
            if ah.have_trigger():
                force_trigger = False
        self.ioexp1.update_pins()
        self.ioexp1.dump_pins()
        # Capture a frame
        self.sqhelper.capture_frame(self.af_helpers, force_trigger)
    def cleanup(self):
        self.serialhdl.clear()
        # Disable ADC
        for ch in range(4):
            self.ioexp1.set_output("dc_connect_ch%d" % (ch,), 0)
        self.ioexp1.set_output("shutdown_adc1", 1)
        self.ioexp1.set_output("shutdown_adc2", 1)
        self.ioexp1.update_pins()
        for ch in range(4):
            self.dac.set_dac(ch, 0.0)
        # Turn off LEDs
        for led in range(4):
            self.ioexp2.set_output("led%d" % (led,), 0)
        self.ioexp2.update_pins()
        sys.stdout.write("\nShutdown adc complete.\n")


######################################################################
# Startup
######################################################################

def setup_serial(serialport):
    import serial
    return serial.Serial(serialport, BAUD, timeout=0.001)

def setup_ft232h(serialport):
    import pyftdi.ftdi
    Ftdi = pyftdi.ftdi.Ftdi
    ser = Ftdi.create_from_url("ftdi://::%s/%d" % (serialport, 1))
    ser.reset()
    ser.set_bitmode(0xff, Ftdi.BitMode.SYNCFF)
    ser.read_data_set_chunksize(0x10000)
    ser.purge_buffers()
    ser.write = ser.write_data
    ser.read = ser.read_data
    time.sleep(.050)
    return ser

def list_ft232h():
    import pyftdi.ftdi
    Ftdi = pyftdi.ftdi.Ftdi
    haas_sn = []
    other_sn = []
    for dev, intf in Ftdi.list_devices():
        if dev.description.startswith("Haasoscope"):
            haas_sn.append(dev.sn)
        else:
            other_sn.append(dev.sn)
    if not haas_sn and not other_sn:
        print("No hi-speed ft232h devices found.")
        return
    if haas_sn:
        print("Found the following Haasoscope devices:")
        for sn in haas_sn:
            print(sn)
    if other_sn:
        print("Found the following ft232h devices:")
        for sn in other_sn:
            print(sn)

def main():
    # Setup command-line options
    usage = "%prog [options] <serialdevice> <output_csv_file>"
    opts = optparse.OptionParser(usage)
    opts.add_option("-u", "--usbhi", action="store_true",
                    help="use hi-speed usb module")
    opts.add_option("-l", "--listusb", action="store_true",
                    help="list hi-speed usb modules")
    hp = HProcessor()
    hp.setup_cmdline_options(opts)

    # Parse command-line
    options, args = opts.parse_args()
    if options.listusb:
        list_ft232h()
        sys.exit(0)
    if len(args) != 2:
        opts.error("Must specify serialdevice and output_csv_file")
    serialport = args[0]
    csvfilename = args[1]
    hp.note_cmdline_options(options, args)
    hp.note_filename(csvfilename)

    # Connect to Haasoscope and capture data
    if options.usbhi:
        ser = setup_ft232h(serialport)
    else:
        ser = setup_serial(serialport)
    try:
        hp.run(ser)
    finally:
        hp.cleanup()

if __name__ == '__main__':
    main()
