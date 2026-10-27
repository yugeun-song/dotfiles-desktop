#!/usr/bin/env python3
"""A USB camera for the VM suite, made with raw_gadget on dummy_hcd.

    usb_camera.py UDC LAYOUT

LAYOUT "laptop" is shaped like this laptop's webcam: an RGB and an IR camera
function, then a HID function, in one device. "plain" is one camera function
alone, the shape of a camera plugged in later.

It answers enumeration and the one class request uvcvideo needs before it
registers a stream (GET_CUR of the probe control), and stalls every other
class request, which uvcvideo tolerates. Nothing is ever streamed: the suite
judges the switch by sysfs and the kernel log, and there are no frames to
look at.
"""

import fcntl
import os
import struct
import sys


def ioc(direction, nr, size):
    return (direction << 30) | (size << 16) | (ord("U") << 8) | nr


NONE, WRITE, READ = 0, 1, 2
RAW_INIT = ioc(WRITE, 0, 257)
RAW_RUN = ioc(NONE, 1, 0)
RAW_EVENT_FETCH = ioc(READ, 2, 8)
RAW_EP0_WRITE = ioc(WRITE, 3, 8)
RAW_EP0_READ = ioc(READ | WRITE, 4, 8)
RAW_CONFIGURE = ioc(NONE, 9, 0)
RAW_VBUS_DRAW = ioc(WRITE, 10, 4)
RAW_EP0_STALL = ioc(NONE, 12, 0)

EVENT_CONTROL = 2
SPEED_HIGH = 3
IO_FLAGS_ZERO = 1
EP0_PACKET = 64
MAX_POWER = 250

YUY2 = bytes([0x59, 0x55, 0x59, 0x32, 0x00, 0x00, 0x10, 0x00,
              0x80, 0x00, 0x00, 0xAA, 0x00, 0x38, 0x9B, 0x71])

# A vendor-defined input report: hid-generic binds it and makes a hidraw
# node, as the presence sensor in the real module does.
REPORT = bytes([0x06, 0x00, 0xFF, 0x09, 0x01, 0xA1, 0x01, 0x15, 0x00, 0x26, 0xFF, 0x00,
                0x75, 0x08, 0x95, 0x01, 0x09, 0x01, 0x81, 0x02, 0xC0])

# UVC 1.1 probe control: format 1, frame 1, 30 fps, 614400-byte frames.
PROBE = struct.pack("<HBBIHHHHHIIIBBBB", 0, 1, 1, 333333, 0, 0, 0, 0, 0,
                    614400, 512, 48000000, 0, 0, 0, 0)


def le16(v):
    return struct.pack("<H", v)


def le32(v):
    return struct.pack("<I", v)


def camera_function(first, name_index, endpoint):
    """IAD, a control interface with a camera and a streaming terminal, and
    a streaming interface with one YUY2 640x480 format on a bulk endpoint."""
    vc, vs = first, first + 1
    camera = bytes([18, 0x24, 0x02, 1]) + le16(0x0201) + bytes([0, 0]) + le16(0) * 3 + bytes([3, 0, 0, 0])
    output = bytes([9, 0x24, 0x03, 2]) + le16(0x0101) + bytes([0, 1, 0])
    header = bytes([13, 0x24, 0x01]) + le16(0x0110) + le16(13 + len(camera) + len(output)) \
        + le32(48000000) + bytes([1, vs])
    fmt = bytes([27, 0x24, 0x04, 1, 1]) + YUY2 + bytes([16, 1, 0, 0, 0, 0])
    frame = bytes([30, 0x24, 0x05, 1, 0]) + le16(640) + le16(480) + le32(147456000) * 2 \
        + le32(614400) + le32(333333) + bytes([1]) + le32(333333)
    input_header = bytes([14, 0x24, 0x01, 1]) + le16(14 + len(fmt) + len(frame)) \
        + bytes([endpoint, 0, 2, 0, 0, 0, 1, 0])
    return (bytes([8, 0x0B, vc, 2, 0x0E, 0x03, 0x00, name_index])
            + bytes([9, 0x04, vc, 0, 0, 0x0E, 0x01, 0x00, name_index]) + header + camera + output
            + bytes([9, 0x04, vs, 0, 1, 0x0E, 0x02, 0x00, 0]) + input_header + fmt + frame
            + bytes([7, 0x05, endpoint, 0x02]) + le16(512) + bytes([0]))


def hid_function(number, endpoint):
    return (bytes([9, 0x04, number, 0, 1, 0x03, 0x00, 0x00, 0])
            + bytes([9, 0x21]) + le16(0x0111) + bytes([0, 1, 0x22]) + le16(len(REPORT))
            + bytes([7, 0x05, endpoint, 0x03]) + le16(8) + bytes([10]))


class Layout:
    def __init__(self, product_id, strings, functions, interfaces, streaming):
        self.device = (bytes([18, 0x01]) + le16(0x0200) + bytes([0xEF, 0x02, 0x01, EP0_PACKET])
                       + le16(0x1209) + le16(product_id) + le16(0x0100) + bytes([1, 2, 3, 1]))
        body = b"".join(functions)
        self.config = bytes([9, 0x02]) + le16(9 + len(body)) + bytes([interfaces, 1, 0, 0x80, MAX_POWER]) + body
        self.strings = strings
        self.streaming = streaming
        self.configuration = 0


def laptop():
    return Layout(0x0001, {1: "dotfiles-desktop", 2: "Test laptop webcam", 3: "VM0001",
                           4: "Test RGB camera", 5: "Test IR camera"},
                  [camera_function(0, 4, 0x81), camera_function(2, 5, 0x82), hid_function(4, 0x83)],
                  5, {1, 3})


def plain():
    return Layout(0x0002, {1: "dotfiles-desktop", 2: "Test plug-in camera", 3: "VM0002",
                           4: "Test camera"},
                  [camera_function(0, 4, 0x81)], 2, {1})


LAYOUTS = {"laptop": laptop, "plain": plain}


def string(text):
    data = text.encode("utf-16-le")
    return bytes([2 + len(data), 0x03]) + data


def ep0_write(fd, data, length):
    data = data[:length]
    flags = IO_FLAGS_ZERO if len(data) < length and len(data) % EP0_PACKET == 0 else 0
    fcntl.ioctl(fd, RAW_EP0_WRITE, struct.pack("<HHI", 0, flags, len(data)) + data)


def ep0_ack(fd):
    fcntl.ioctl(fd, RAW_EP0_READ, bytearray(struct.pack("<HHI", 0, 0, 0)), True)


def handle(fd, setup, dev):
    request_type, request, value, index, length = struct.unpack("<BBHHH", setup)
    standard = request_type & 0x60 == 0
    if standard and request == 6:
        kind, number = value >> 8, value & 0xFF
        data = {1: dev.device, 2: dev.config, 0x22: REPORT}.get(kind)
        if kind == 3:
            data = bytes([4, 0x03]) + le16(0x0409) if number == 0 else (
                string(dev.strings[number]) if number in dev.strings else None)
        if data is None:
            fcntl.ioctl(fd, RAW_EP0_STALL, 0)
        else:
            ep0_write(fd, data, length)
    elif standard and request == 9:
        # Configuration 0 is how the host unconfigures a deauthorized device.
        if value:
            fcntl.ioctl(fd, RAW_VBUS_DRAW, MAX_POWER)
            fcntl.ioctl(fd, RAW_CONFIGURE, 0)
        dev.configuration = value
        ep0_ack(fd)
    elif standard and request == 0:
        ep0_write(fd, b"\0\0", length)
    elif standard and request == 8:
        ep0_write(fd, bytes([dev.configuration]), length)
    elif standard and request == 10:
        ep0_write(fd, b"\0", length)
    elif standard and request in (1, 3, 11):
        ep0_ack(fd)
    elif request_type == 0xA1 and request == 0x81 and value >> 8 == 0x01 and index & 0xFF in dev.streaming:
        ep0_write(fd, PROBE.ljust(length, b"\0"), length)
    else:
        fcntl.ioctl(fd, RAW_EP0_STALL, 0)


def main(udc, layout):
    dev = LAYOUTS[layout]()
    fd = os.open("/dev/raw-gadget", os.O_RDWR)
    fcntl.ioctl(fd, RAW_INIT, struct.pack("128s128sB", b"dummy_udc", udc.encode(), SPEED_HIGH))
    fcntl.ioctl(fd, RAW_RUN, 0)
    print(f"{layout} camera on {udc}", flush=True)
    while True:
        event = bytearray(struct.pack("<II", 0, 8) + bytes(8))
        fcntl.ioctl(fd, RAW_EVENT_FETCH, event, True)
        kind, length = struct.unpack("<II", event[:8])
        if kind != EVENT_CONTROL:
            continue
        setup = bytes(event[8:8 + length])
        try:
            handle(fd, setup, dev)
        except OSError as e:
            # The host gives up on a request when it resets or deconfigures.
            print(f"request {setup.hex()}: {e}", flush=True)


if __name__ == "__main__":
    if len(sys.argv) != 3 or sys.argv[2] not in LAYOUTS:
        print("usage: usb_camera.py UDC laptop|plain", file=sys.stderr)
        sys.exit(2)
    main(sys.argv[1], sys.argv[2])
