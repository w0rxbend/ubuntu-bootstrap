#!/usr/bin/env python3
"""Press a key chord in the live session through a throwaway uinput keyboard (needs root for /dev/uinput).

    sudo -n python3 tests/lib/uinput_keys.py super+3
    sudo -n python3 tests/lib/uinput_keys.py super+shift+1

Only what the gnome assertions need: Super/Shift/Ctrl/Alt plus the digits 1..9. Used by
tests/assertions/gnome.sh when ASSERT_LIVE_INPUT=1 to prove that Super+N really switches workspace (the compositor
sees the keys like a real keyboard's, so a stray grab by Zorin Dash etc. would show up). No third-party modules.
"""
import fcntl
import os
import struct
import sys
import time

UI_SET_EVBIT, UI_SET_KEYBIT, UI_DEV_CREATE, UI_DEV_DESTROY = 0x40045564, 0x40045565, 0x5501, 0x5502
EV_SYN, EV_KEY = 0x00, 0x01
MODS = {"super": 125, "shift": 42, "ctrl": 29, "alt": 56}  # KEY_LEFTMETA, KEY_LEFTSHIFT, KEY_LEFTCTRL, KEY_LEFTALT
DIGITS = {str(i): 1 + i for i in range(1, 10)}  # KEY_1 = 2 .. KEY_9 = 10


def main(chord: str) -> int:
    parts = chord.lower().split("+")
    mods, key = parts[:-1], parts[-1]
    if key not in DIGITS or any(m not in MODS for m in mods):
        print(f"unsupported chord: {chord}", file=sys.stderr)
        return 2
    fd = os.open("/dev/uinput", os.O_WRONLY | os.O_NONBLOCK)
    try:
        fcntl.ioctl(fd, UI_SET_EVBIT, EV_KEY)
        fcntl.ioctl(fd, UI_SET_EVBIT, EV_SYN)
        for code in list(MODS.values()) + list(DIGITS.values()):
            fcntl.ioctl(fd, UI_SET_KEYBIT, code)
        # struct uinput_user_dev: name[80], input_id{bustype=BUS_VIRTUAL, vendor, product, version}, ff_effects_max,
        # absmax/absmin/absfuzz/absflat[ABS_CNT=64]
        os.write(fd, struct.pack("80sHHHHi", b"zorin-bootstrap-test-kbd", 0x06, 0x1, 0x1, 1, 0) + b"\0" * (4 * 64 * 4))
        fcntl.ioctl(fd, UI_DEV_CREATE)
        time.sleep(1.0)  # let libinput/mutter pick the new device up

        def emit(code: int, value: int) -> None:
            os.write(fd, struct.pack("llHHi", 0, 0, EV_KEY, code, value))
            os.write(fd, struct.pack("llHHi", 0, 0, EV_SYN, 0, 0))
            time.sleep(0.05)

        held = [MODS[m] for m in mods]
        for code in held:
            emit(code, 1)
        emit(DIGITS[key], 1)
        emit(DIGITS[key], 0)
        for code in reversed(held):
            emit(code, 0)
        time.sleep(0.5)
        fcntl.ioctl(fd, UI_DEV_DESTROY)
    finally:
        os.close(fd)
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    sys.exit(main(sys.argv[1]))
