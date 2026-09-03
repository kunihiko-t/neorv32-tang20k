import serial, sys, time
port, baud, secs = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
ser = serial.Serial(port, baud, timeout=1)
t0 = time.time()
buf = b''
while time.time() - t0 < secs:
    data = ser.read(256)
    if data:
        buf += data
print(f"[{len(buf)} bytes] {buf!r}")
