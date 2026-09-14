# ADS7039 FPGA UART Reader

A SystemVerilog-based FPGA project for interfacing with the Texas Instruments ADS7039 ADC and transmitting sampled ADC data to a PC over UART.

## Features

- ADS7039 SPI interface
- SystemVerilog implementation
- FPGA-based ADC data acquisition
- UART transmission at 115200 baud
- Real-time ADC monitoring on a PC
- Python interface for receiving and displaying ADC samples

## System Architecture

Analog Signal
     |
     v
+------------+
|  ADS7039   |
|    ADC     |
+------------+
     |
     | SPI
     v
+----------------+
|      FPGA      |
|                |
| ADS7039 Reader |
|      +         |
| UART Transmitter|
+----------------+
     |
     | UART
     v
+----------------+
|       PC       |
|     Python     |
+----------------+

## FPGA Design

The FPGA communicates with the ADS7039 using SPI. The ADC conversion data is captured by the SystemVerilog ADC reader and then passed to a UART transmitter.

The UART interface sends each ADC sample to the PC for real-time monitoring.

## UART Configuration

- Baud rate: 115200
- Data bits: 8
- Stop bits: 1
- Parity: None

## Python

The Python program uses the serial port to receive ADC data from the FPGA.

Example:

```python
import serial

ser = serial.Serial(
    port="COM3",
    baudrate=115200,
    timeout=1
)

while True:
    data = ser.readline().decode().strip()

    if data:
        print("ADC:", data)
