"""pad_bridge.py - send a USB gamepad to the Nexys A7 over the board's USB-UART cable.

Setup (once):      pip install pygame pyserial
Find buttons:      python pad_bridge.py --test          (press buttons, see their numbers; nothing is sent)
List serial ports: python pad_bridge.py --list
Play:              python pad_bridge.py --port COM5     (use the COM port of the board, see --list)

Keep this window open while playing. If it is closed or the cable is pulled the FPGA
releases every button after half a second.

Packet (2 bytes, 60 times per second):
  byte 0 = 0 s6..s0    byte 1 = 1 s13..s7        (must match pad_input.v)
Bits: 0 up, 1 down, 2 left, 3 right, 4 A, 5 X, 6 Y, 7 B, 8 Start, 9 Back, 10 RB
In the game:  D-pad / left stick = move,  A = tap egg / confirm / restart,
              X = ELECTRIC on/off,  Y = POISON on/off,  B = dash,
              Start = pause on/off,  Back = new game (hold),  RB = end game on/off
"""
import argparse
import os
import sys
import time

BAUD = 115200
RATE_HZ = 60
STICK_DEADZONE = 0.5

# Button numbers as pygame sees them. These are right for an Xbox-style (X-Input) pad.
# If the pad is in D-Input mode the numbers are different: run --test and edit here.
BUTTON_INDEX = {"a": 0, "b": 1, "x": 2, "y": 3, "rb": 5, "back": 6, "start": 7}

# Raw layout for the generic pad identified by --test on this setup.
GENERIC_PAD = ("Gamepad", 15, 1, 6)

def raw_skill_indexes(js):
    identity = (js.get_name(), js.get_numbuttons(), js.get_numhats(), js.get_numaxes())
    return (3, 4) if identity == GENERIC_PAD else (BUTTON_INDEX["x"], BUTTON_INDEX["y"])


BIT = {"up": 0, "down": 1, "left": 2, "right": 3, "a": 4, "x": 5, "y": 6,
       "b": 7, "start": 8, "back": 9, "rb": 10}


def encode_packet(pressed):
    """pressed: set of names from BIT. Returns the 2 bytes sent to the FPGA."""
    s = 0
    for name in pressed:
        s |= 1 << BIT[name]
    return bytes([s & 0x7F, 0x80 | ((s >> 7) & 0x7F)])


def read_pad(js, mapped, skill_buttons):
    pressed = set()
    if js is None:
        return pressed
    for name, default_idx in BUTTON_INDEX.items():
        idx, logical_button = skill_buttons.get(name, (default_idx, None))
        if logical_button is not None and mapped is not None:
            is_down = mapped.get_button(logical_button)
        else:
            is_down = idx < js.get_numbuttons() and js.get_button(idx)
        if is_down:
            pressed.add(name)
    if js.get_numhats() > 0:
        hx, hy = js.get_hat(0)
        if hy > 0: pressed.add("up")
        if hy < 0: pressed.add("down")
        if hx < 0: pressed.add("left")
        if hx > 0: pressed.add("right")
    if js.get_numaxes() >= 2:
        ax, ay = js.get_axis(0), js.get_axis(1)
        if ay < -STICK_DEADZONE: pressed.add("up")
        if ay > STICK_DEADZONE: pressed.add("down")
        if ax < -STICK_DEADZONE: pressed.add("left")
        if ax > STICK_DEADZONE: pressed.add("right")
    return pressed


def main():
    ap = argparse.ArgumentParser(description="Gamepad to Nexys A7 UART bridge")
    ap.add_argument("--port", help="serial port of the board, e.g. COM5")
    ap.add_argument("--list", action="store_true", help="list serial ports and exit")
    ap.add_argument("--test", action="store_true", help="show pad buttons, send nothing")
    ap.add_argument("--x-button", type=int, help="override raw Electric button index")
    ap.add_argument("--y-button", type=int, help="override raw Poison button index")
    args = ap.parse_args()
    if any(index is not None and index < 0 for index in (args.x_button, args.y_button)):
        ap.error("button indexes must be non-negative")

    if args.list:
        import serial.tools.list_ports
        for p in serial.tools.list_ports.comports():
            print(p.device, "-", p.description)
        return

    os.environ.setdefault("SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS", "1")
    os.environ.setdefault("SDL_VIDEODRIVER", "dummy")
    import pygame
    pygame.init()
    pygame.joystick.init()
    from pygame._sdl2 import controller
    controller.init()
    js = None
    mapped = None
    skill_buttons = {}
    ser = None
    if not args.test:
        if not args.port:
            sys.exit("Give the board's port with --port COMx (see --list).")
        import serial
        ser = serial.Serial(args.port, BAUD, timeout=0)
        print("Serial port open:", args.port)

    last_shown = None
    period = 1.0 / RATE_HZ
    next_t = time.time()
    print("Running. Ctrl+C to stop.")
    try:
        while True:
            pygame.event.pump()
            if js is None and pygame.joystick.get_count() > 0:
                js = pygame.joystick.Joystick(0)
                mapped = controller.Controller(0) if controller.is_controller(0) else None
                raw_x, raw_y = raw_skill_indexes(js)
                skill_buttons = {
                    "x": (raw_x, pygame.CONTROLLER_BUTTON_X) if args.x_button is None else (args.x_button, None),
                    "y": (raw_y, pygame.CONTROLLER_BUTTON_Y) if args.y_button is None else (args.y_button, None),
                }
                if mapped is None:
                    print("Raw skill mapping: X =", skill_buttons["x"][0], "| Y =", skill_buttons["y"][0])
                print("Gamepad found:", js.get_name(), "| buttons", js.get_numbuttons(),
                      "| hats", js.get_numhats(), "| axes", js.get_numaxes())
            if js is not None and pygame.joystick.get_count() == 0:
                print("Gamepad lost")
                if mapped is not None:
                    mapped.quit()
                    mapped = None
                js = None

            pressed = read_pad(js, mapped, skill_buttons)
            if args.test:
                if js is not None:
                    raw = [i for i in range(js.get_numbuttons()) if js.get_button(i)]
                    shown = (sorted(raw), sorted(pressed))
                    if shown != last_shown:
                        print("raw buttons:", shown[0], "| game inputs:", shown[1])
                        last_shown = shown
            else:
                ser.write(encode_packet(pressed))
                shown = sorted(pressed)
                if shown != last_shown:
                    print("sending:", shown)
                    last_shown = shown

            next_t += period
            delay = next_t - time.time()
            if delay > 0:
                time.sleep(delay)
            else:
                next_t = time.time()
    except KeyboardInterrupt:
        print("Stopped.")
    finally:
        if ser is not None:
            ser.write(encode_packet(set()))   # release all buttons
            ser.close()


if __name__ == "__main__":
    main()
