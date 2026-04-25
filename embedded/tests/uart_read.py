import serial
import serial.tools.list_ports
import time

BAUD_RATE = 115200

def list_available_ports():
    """List all available COM ports"""
    ports = serial.tools.list_ports.comports()
    print("\n=== Available COM Ports ===")
    for port in ports:
        print(f"  {port.device}: {port.description}")
    print()
    return [port.device for port in ports]

def auto_detect_esp32():
    """Try to find ESP32-C3 by description"""
    ports = serial.tools.list_ports.comports()
    for port in ports:
        desc = port.description.lower()
        if 'usb serial' in desc or 'cp210' in desc or 'ch340' in desc or 'esp32' in desc:
            return port.device
    return None

# List available ports
available_ports = list_available_ports()

# Try to auto-detect
auto_port = auto_detect_esp32()
if auto_port:
    print(f"Auto-detected possible ESP32 on: {auto_port}")
    PORT = auto_port
else:
    PORT = input("Enter COM port (e.g., COM3): ").strip()
    if not PORT:
        PORT = 'COM3'

print(f"\nAttempting to connect to {PORT} at {BAUD_RATE} baud...")

try:
    ser = serial.Serial(PORT, BAUD_RATE, timeout=2)
    print(f"✓ Port opened successfully")
    print(f"Waiting for data... (Ctrl+C to stop)\n")
    
    timeout_counter = 0
    max_timeout = 10  # seconds
    
    while True:
        if ser.in_waiting > 0:
            timeout_counter = 0  # Reset timeout on data
            line = ser.readline().decode('utf-8', errors='ignore').strip()
            
            # Try to parse as CSV data
            try:
                bp, br, fp, fr = line.split(',')
                print(f"Bicep: [Pitch: {bp:>6}°, Roll: {br:>6}°]  |  Wrist: [Pitch: {fp:>6}°, Roll: {fr:>6}°]")
            except ValueError:
                # Print raw data (boot messages, etc.)
                print(f"[RAW] {line}")
        else:
            time.sleep(0.1)
            timeout_counter += 0.1
            
            if timeout_counter >= max_timeout:
                print(f"\n⚠ No data received for {max_timeout} seconds")
                print("Troubleshooting:")
                print("  1. Press the RESET button on your ESP32-C3")
                print("  2. Check Device Manager for the correct COM port")
                print("  3. Verify the device isn't in bootloader mode")
                print("  4. Try unplugging and replugging the USB cable")
                timeout_counter = 0  # Reset and keep trying
                
except serial.SerialException as e:
    print(f"\n✗ Error opening serial port: {e}")
    print("\nTroubleshooting:")
    print("  1. Close PlatformIO Serial Monitor if open")
    print("  2. Check the correct COM port in Device Manager")
    print("  3. Try a different USB cable or port")
    print("  4. Verify drivers are installed")
    
except KeyboardInterrupt:
    print("\n\nExiting...")
    
finally:
    if 'ser' in locals() and ser.is_open:
        ser.close()
        print("Serial port closed")