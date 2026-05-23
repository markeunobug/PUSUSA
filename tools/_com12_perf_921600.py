import serial, struct, time, sys
PORT='COM12'; BAUD=921600

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
    return b'\xAA' + body + crc16_modbus(body).to_bytes(2,'big') + b'\x55'

def read_exact(ser,n,deadline):
    out=b''
    while len(out)<n and time.time()<deadline:
        chunk=ser.read(n-len(out))
        if chunk:
            out+=chunk
    return out

def read_frame(ser, timeout=3.0):
    deadline=time.time()+timeout
    while time.time()<deadline:
        b=ser.read(1)
        if not b:
            continue
        if b!=b'\xAA':
            continue
        hdr=read_exact(ser,3,deadline)
        if len(hdr)<3:
            return None
        ln=int.from_bytes(hdr[:2],'big'); cmd=hdr[2]
        rest=read_exact(ser,ln+3,deadline)
        if len(rest)<ln+3:
            return None
        payload=rest[:ln]
        crc=int.from_bytes(rest[ln:ln+2],'big')
        tail=rest[-1]
        calc=crc16_modbus(hdr+payload)
        return {'cmd':cmd,'len':ln,'crc_ok':crc==calc,'tail_ok':tail==0x55,'payload':payload}
    return None

try:
    ser=serial.Serial(PORT,BAUD,timeout=0.02)
except Exception as e:
    print('SERIAL_OPEN_ERROR',repr(e))
    sys.exit(1)
ser.reset_input_buffer(); ser.reset_output_buffer()
set_freq_payload = struct.pack('>dddd', 0.0, 65_000_000.0, 32_500_000.0, 65_000_000.0)
set_sweep_payload = struct.pack('>dBH', 10.0, 0, 256)
for cmd,payload in [(0x01,set_freq_payload),(0x05,set_sweep_payload)]:
    ser.write(build_frame(cmd,payload))
    f=read_frame(ser,1.0)
    print('CFG',cmd,f and (hex(f['cmd']),f['len'],f['crc_ok'],f['tail_ok']))

rtts=[]
for i in range(5):
    ser.reset_input_buffer()
    t0=time.perf_counter()
    ser.write(build_frame(0x06,b''))
    ack=read_frame(ser,1.0)
    data=read_frame(ser,2.0)
    dt=(time.perf_counter()-t0)*1000
    print('ITER',i,'ACK',None if not ack else (hex(ack['cmd']),ack['len']))
    print('ITER',i,'DATA',None if not data else (hex(data['cmd']),data['len']))
    if data and data['cmd']==0x82:
        pts=int.from_bytes(data['payload'][:2],'big')
        ts=int.from_bytes(data['payload'][2:6],'big')
        print('ITER',i,'POINTS',pts,'TS',ts)
    print('ITER',i,'RTT_MS',round(dt,1))
    rtts.append(dt)
    time.sleep(0.05)
print('RTT_AVG_MS',round(sum(rtts)/len(rtts),1))
ser.close()
