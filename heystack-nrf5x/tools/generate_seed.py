
import os
import hashlib
import binascii
import struct
import re
import argparse
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.primitives import serialization

def generate_seed():
    return os.urandom(32)

def derive_key(seed, counter):
    # Match firmware logic: SHA256(seed || counter_BE)
    message = seed + struct.pack('>I', counter)
    digest = hashlib.sha256(message).digest()
    
    # Use first 28 bytes as private key (simplification matching fw)
    private_value = int.from_bytes(digest[:28], byteorder='big')
    
    # Create private key object
    private_key = ec.derive_private_key(private_value, ec.SECP224R1())
    
    # Get public key numbers
    public_numbers = private_key.public_key().public_numbers()
    x = public_numbers.x
    
    # X coordinate as 28 bytes
    x_bytes = x.to_bytes(28, byteorder='big')
    return x_bytes

def update_firmware(seed, main_c_path):
    print(f"\n[Updating Firmware] {main_c_path}")
    if not os.path.exists(main_c_path):
        print("Error: main.c not found!")
        return False
        
    try:
        with open(main_c_path, 'r', encoding='utf-8') as f:
            content = f.read()

        # Format seed as C array content
        c_array_content = "    " + ",\n    ".join(
            ", ".join(f"0x{b:02x}" for b in seed[i:i+8]) 
            for i in range(0, 32, 8)
        )
        
        # Regex to find the m_master_key_seed block
        # static const uint8_t m_master_key_seed[32] = { ... };
        pattern = r"(static\s+const\s+uint8_t\s+m_master_key_seed\[32\]\s*=\s*\{)([^}]+)(\}\s*;)"
        
        if re.search(pattern, content, re.DOTALL):
            new_content = re.sub(
                pattern, 
                f"\\1\n{c_array_content}\n\\3", 
                content, 
                flags=re.DOTALL
            )
            
            with open(main_c_path, 'w', encoding='utf-8') as f:
                f.write(new_content)
            print("Successfully updated m_master_key_seed in main.c")
            return True
        else:
            print("Error: Could not find 'm_master_key_seed' definition in main.c")
            return False

    except Exception as e:
        print(f"Error updating file: {e}")
        return False

def main():
    parser = argparse.ArgumentParser(description='nRF52 AirTag Key Generator')
    parser.add_argument('--main-c', default='../main.c', help='Path to main.c file (default: ../main.c)')
    parser.add_argument('--no-update', action='store_true', help='Do not update main.c automatically')
    args = parser.parse_args()

    print("=== nRF52 AirTag Key Generator ===")
    seed = generate_seed()
    
    print("\n[Generated Master Seed]")
    print(f"Hex: {seed.hex()}")
    
    updated = False
    
    # Attempt to update main.c if not disabled
    target_file = os.path.join(os.path.dirname(os.path.abspath(__file__)), args.main_c)
    if not args.no_update:
        if os.path.exists(target_file):
            updated = update_firmware(seed, target_file)
        else:
            # Try loading relative to CWD if script path failed
            if os.path.exists(args.main_c):
                updated = update_firmware(seed, args.main_c)
            else:
                print(f"Warning: main.c not found at {target_file} or {args.main_c}. Skipping update.")
    
    if not updated:
        print("\n[Manual Update Required]")
        print("C Array:")
        print("{")
        for i in range(0, 32, 8):
            line = ", ".join(f"0x{b:02x}" for b in seed[i:i+8])
            print(f"    {line},")
        print("};")
    
    print("\n[Verification Keys]")
    print("Counter | Public Key (First 28 bytes of X) | Base64 (FindMy)")
    print("-" * 65)
    
    for i in range(5):
        key = derive_key(seed, i)
        try:
             b64 = binascii.b2a_base64(key).decode().strip()
        except:
             b64 = "Error"
        print(f"{i:7} | {key.hex()} | {b64}")
        
    print("\nINSTRUCTIONS:")
    if updated:
         print("1. Firmware file 'main.c' has been updated automatically.")
    else:
         print("1. Copy the C Array above into 'main.c' replacing 'm_master_key_seed'.")
    print("2. Flash the firmware.")
    print("3. Use these keys to verify the firmware is generating the correct sequence.")

if __name__ == "__main__":
    try:
        main()
    except ImportError:
        print("Error: 'cryptography' library not found.")
        print("Please install it using: pip install cryptography")
