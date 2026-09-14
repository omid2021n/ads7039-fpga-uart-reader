#!/usr/bin/env python3
"""
Read 10-bit ADC samples from FPGA over UART and plot voltage live (low-latency).

ADC  : ADS7039-Q1 (10-bit SAR ADC)
VREF : 3.3 V
PORT : /dev/ttyUSB0
BAUD : 115200

UART frame format (2 bytes per sample):
    Byte 1: {6'b0, adc[9:8]}
    Byte 2: adc[7:0]

Usage:
    python3 ADC_reader.py
    python3 ADC_reader.py --port /dev/ttyUSB0 --baud 115200 --vref 3.3
    python3 ADC_reader.py --save adc_log.csv
"""

import argparse
import time
import threading
import queue
from collections import deque

# --- Use Tk backend to avoid Qt/Wayland warnings on Ubuntu ---
import matplotlib
matplotlib.use("TkAgg")

import matplotlib.pyplot as plt
import matplotlib.animation as animation
import serial


# ----------------------------------------------------------------
#  Command-line arguments
# ----------------------------------------------------------------
def parse_args():
    p = argparse.ArgumentParser(description="Read 10-bit ADC from FPGA over UART")
    p.add_argument("--port",   default="/dev/ttyUSB1", help="Serial port")
    p.add_argument("--baud",   type=int,   default=115200, help="Baud rate")
    p.add_argument("--vref",   type=float, default=3.3,    help="ADC reference voltage (V)")
    p.add_argument("--window", type=int,   default=500,
                   help="Number of samples shown in the live plot")
    p.add_argument("--save",   default=None, help="Optional CSV file to log data")
    return p.parse_args()


# ----------------------------------------------------------------
#  Background serial reader thread
#  Reads bytes continuously and pushes (adc, voltage) into a queue.
#  Never blocks the GUI.
# ----------------------------------------------------------------
def serial_reader_thread(port, baud, vref, sample_queue, stop_event):
    try:
        ser = serial.Serial(port, baud, timeout=0.01)
        time.sleep(0.3)
        ser.reset_input_buffer()
        print(f"[reader] Opened {port} @ {baud} baud")
    except serial.SerialException as e:
        print(f"[reader] Serial error: {e}")
        print("Check the port name (ls /dev/ttyUSB*) and permissions (dialout group).")
        stop_event.set()
        return

    buf = bytearray()
    while not stop_event.is_set():
        try:
            chunk = ser.read(64)
        except serial.SerialException as e:
            print(f"[reader] Read error: {e}")
            break

        if not chunk:
            continue

        buf.extend(chunk)

        # Process every complete 2-byte frame in the buffer
        while len(buf) >= 2:
            b1 = buf.pop(0)
            b2 = buf.pop(0)
            high = b1 & 0x03                  # 10-bit ADC
            low  = b2
            adc  = (high << 8) | low          # 0..1023
            voltage = adc * vref / 1024.0

            try:
                sample_queue.put_nowait((adc, voltage))
            except queue.Full:
                # Drop the oldest sample to keep up
                try:
                    sample_queue.get_nowait()
                except queue.Empty:
                    pass
                try:
                    sample_queue.put_nowait((adc, voltage))
                except queue.Full:
                    pass

    try:
        ser.close()
        print("[reader] Serial port closed")
    except Exception:
        pass


# ----------------------------------------------------------------
#  Live plotter — voltage only, drains queue every frame
# ----------------------------------------------------------------
def run_live_plot(args):
    raw_buf = deque(maxlen=args.window)
    v_buf   = deque(maxlen=args.window)
    t_buf   = deque(maxlen=args.window)

    csv_file = open(args.save, "w") if args.save else None
    if csv_file:
        csv_file.write("time_s,adc_code,voltage_V\n")

    # --- Start background reader thread ---
    sample_q   = queue.Queue(maxsize=5000)
    stop_event = threading.Event()
    reader = threading.Thread(
        target=serial_reader_thread,
        args=(args.port, args.baud, args.vref, sample_q, stop_event),
        daemon=True,
    )
    reader.start()

    # --- Figure ---
    fig, ax = plt.subplots(figsize=(10, 5))
    fig.suptitle(f"ADC7039 Live Voltage  ({args.port} @ {args.baud} baud)")

    (line_v,) = ax.plot([], [], color="tab:blue", lw=1.2, label="Voltage")

    ax.set_ylabel("Voltage (V)")
    ax.set_xlabel("Time (s)")
    ax.set_ylim(0, args.vref * 1.05)
    ax.grid(True, alpha=0.3)
    ax.legend(loc="upper left")

    t0 = time.time()
    last_data_time = [time.time()]     # mutable so closure can update it

    # --- Info text box: TOP-RIGHT ---
    text_info = ax.text(
        0.98, 0.95, "waiting for data...",
        transform=ax.transAxes,
        va="top", ha="right",
        family="monospace", fontsize=11,
        bbox=dict(boxstyle="round,pad=0.4",
                  facecolor="white", alpha=0.8, edgecolor="gray")
    )

    # ------------------------------------------------------------
    #  Animation callback — drains queue fast, never blocks
    # ------------------------------------------------------------
    def update(_frame):
        drained = 0
        while True:
            try:
                adc, v = sample_q.get_nowait()
            except queue.Empty:
                break

            t = time.time() - t0
            raw_buf.append(adc)
            v_buf.append(v)
            t_buf.append(t)
            drained += 1

            if csv_file:
                csv_file.write(f"{t:.6f},{adc},{v:.6f}\n")

            if drained >= 10000:            # safety cap per frame
                break

        if drained > 0:
            last_data_time[0] = time.time()

        if t_buf:
            ts = list(t_buf)
            vs = list(v_buf)
            rs = list(raw_buf)

            line_v.set_data(ts, vs)
            if ts[-1] - ts[0] > 0:
                ax.set_xlim(ts[0], ts[-1])

            text_info.set_text(
                f"last V    = {vs[-1]:6.4f} V\n"
                f"min  V    = {min(vs):6.4f} V\n"
                f"max  V    = {max(vs):6.4f} V\n"
                f"avg  V    = {sum(vs)/len(vs):6.4f} V\n"
                f"last code = {rs[-1]:4d}\n"
                f"samples   = {len(rs)}"
            )
        else:
            silent_for = time.time() - last_data_time[0]
            if silent_for < 1.0:
                text_info.set_text("waiting for data...")
            else:
                text_info.set_text(f"no data on {args.port}\n"
                                   f"check FPGA / cable / port")

        return line_v, text_info

    try:
        _ani = animation.FuncAnimation(
            fig, update, interval=30, blit=False, cache_frame_data=False
        )
        plt.tight_layout()
        plt.show()
    except KeyboardInterrupt:
        print("\nStopped by user.")
    finally:
        stop_event.set()
        reader.join(timeout=1.0)
        if csv_file:
            csv_file.close()
            print(f"Data saved to {args.save}")


# ----------------------------------------------------------------
#  Entry point
# ----------------------------------------------------------------
if __name__ == "__main__":
    args = parse_args()
    run_live_plot(args)
