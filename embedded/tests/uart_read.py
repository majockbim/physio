import serial
import time

PORT = 'COM3' # change to match
BAUD_RATE = 115200

try:
    ser = serial.Serial(PORT, BAUD_RATE, timeout=1)
    print(f"listening on {PORT} at {BAUD_RATE} baud...")
    print("Ctrl+C to stop.\n")
    
    while True:
        if ser.in_waiting > 0:
            # read the incoming line, decode bytes to string, and strip the \n
            line = ser.readline().decode('utf-8').strip()
            
            # formatting
            try:
                bp, br, fp, fr = line.split(',')
                print(f"Bicep: [Pitch: {bp:>6}°, Roll: {br:>6}°]  |  Forearm: [Pitch: {fp:>6}°, Roll: {fr:>6}°]")
            except ValueError:
                # catch boot-up text or incomplete lines
                print(f"Raw: {line}")
                
except serial.SerialException as e:
    print(f"\nError opening serial port: {e}")
    print("Did you forget to close the PlatformIO Serial Monitor?")
except KeyboardInterrupt:
    print("\nExiting...")
finally:
    if 'ser' in locals() and ser.is_open:
        ser.close()