This document describes the communication protocol between FPGA and
host capture software.

# Message Protocol

The message protocol is a binary protocol.  All messages to and from
the FPGA have the following format:
`<1-byte msgid><2-byte lenseq><n-byte data><2-byte crc><1-byte sync>`

The `msgid` indicates the type of content found in the remainder of
the message.  The `lenseq` is a 2-byte little endian encoded value
containing a sequence number in the lower 6 bits and the data length
in the top 10 bits. The data length determines the number of bytes
contained in the following `data` field.  The `data` field contains
data (the data contents are determined by the msgid field).  The `crc`
field contains a 16-bit CRC-16-CCITT of the message (covering msgid to
data).  The `sync` field is 0x7e.

The following `msgid` are available:
- REQUEST (0x52): Messages generated from the host capture software
  intended for the FPGA.  There is always exactly four bytes of data
  in these messages.  The data has the following format:
  `<1 byte write_flag><2-byte address><1-byte write_data>`

  The `write_flag` is either 0x80 to indicate a write to the given
  address or 0x00 to indicate a read of the given address.  The
  `address` field is the register address to read or write (encoded in
  little-endian).  The `write_data` is the data to write for write
  requests (the field must be present for read requests, but is
  otherwise ignored).

- RESPONSE (0x60): Messages generated from the FPGA in response to a
  valid REQUEST message.  The FPGA generates this message for valid
  read and valid write request messages.  There is always exactly two
  bytes of data in these messages.  The data has the following format:
  `<1-byte req_errseq><1 byte read_data>`

  The `req_errseq` contains a sequence error bit in the top bit and
  the next expected sequence number of a REQUEST message in the lower
  six bits.  (For valid requests, the next expected sequence number is
  always one greater than the message that generated the message.)
  The sequence error field is 0x00 for normal responses and is 0x01 if
  the FPGA received a valid request with an incorrect sequence number.
  The `read_data` contains the associated data from a valid read
  request (the field is present in response to write requests, but
  only contains valid data on read requests).

  If sequence error bit is set then the requested message was not
  processed by the FPGA.  In this case the `read_data` field should be
  ignored.  The host should resend the request using the sequence
  number found in the `req_errseq` field.

- SAMPLE (0x61): Messages generated by the FPGA containing data from
  its internal "samples queue".  There may be between 1 and 1023 bytes
  in each message.  The contents of each message are dependent on the
  configuration of the FPGA "samples queue".

# Register Addresses

Each REQUEST message sent to the FPGA generates an internal
transaction on the FPGA's wishbone bus.  The transaction can either be
a read transaction (read data from a register at an address) or a
write transaction (write data to a register at an address).  The FPGA
then responds with a RESPONSE message.  For read requests, the
RESPONSE message will contain the data read from the requested
address.

The registers at each address can be found in the
[fpgaregs.py](../src/fpgaregs.py) module.  The fields within those
registers are not currently documented.
