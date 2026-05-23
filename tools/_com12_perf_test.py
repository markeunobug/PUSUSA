import serial, struct, time

PORT='COM12'
BAUD=115200

def crc16_modbus(data: bytes) -> int:
    crc = 0xFFFF
    for b in data:
        crc ^= b
        for _ in range(8):
            if crc & 1:
                crc = (crc >> 1) ^ 0xA001
            else:
                crc >>= 1
    return crc & 0xFFFF

def build_frame(cmd:int, payload:bytes=b'') -> bytes:
    body = len(payload).to_bytes(2,'big') + bytes([cmd]) + payload
    crc = crc16_modbus(body).to_bytes(2,'big')
    return b'\xAA' + body + crc + b'\x55'

def read_frame(ser, timeout=1.0):
    end = time.time() + timeout
    while time.time() < end:
        b = ser.read(1)
        if not b:
            continue
        if b != b'\xAA':
            continue
        hdr = ser.read(3)
        if len(hdr) < 3:
            return None
        ln = int.from_bytes(hdr[:2],'big')
        cmd = hdr[2]
        rest = ser.read(ln + 3)
        if len(rest) < ln + 3:
            return None
        payload = rest[:ln]
        crc = int.from_bytes(rest[ln:ln+2],'big')
        tail = rest[-1]
        if tail != 0x55:
            continue
        calc = crc16_modbus(hdr + payload)
        if crc != calc:
            continue
        return cmd, payload
    return None

ser = serial.Serial(PORT, BAUD, timeout=0.05)
ser.reset_input_buffer(); ser.reset_output_buffer()
# configure host-like range 0~65MHz, 256 points
set_freq_payload = struct.pack('>dddd', 0.0, 65_000_000.0, 32_500_000.0, 65_000_000.0)
set_sweep_payload = struct.pack('>dBH', 10.0, 0, 256)
for cmd,payload in [(0x01,set_freq_payload),(0x05,set_sweep_payload)]:
    ser.write(build_frame(cmd,payload))
    a = read_frame(ser, 1.0)
    print('CFG_ACK', cmd, a)

rtts=[]
for i in range(10):
    t0=time.perf_counter()
    ser.write(build_frame(0x06,b''))
    f1=read_frame(ser,1.0)
    f2=read_frame(ser,2.0)
    dt=(time.perf_counter()-t0)*1000
    ok = f1 and f2 and f1[0]==0x81 and f2[0]==0x82
    pts = None
    if ok:
        pts = int.from_bytes(f2[1][:2],'big')
    print('REQ', i, 'ok=', ok, 'rtt_ms=', round(dt,1), 'pts=', pts, 'ack_cmd=', None if not f1 else hex(f1[0]), 'data_cmd=', None if not f2 else hex(f2[0]))
    rtts.append(dt)
    time.sleep(0.1)
print('RTT_AVG_MS', round(sum(rtts)/len(rtts),1))
ser.close()
