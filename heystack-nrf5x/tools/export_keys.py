
import os
import hashlib
import binascii
import struct
import argparse
import json
import time
import re
from cryptography.hazmat.primitives.asymmetric import ec

# Default rotation interval (must match firmware)
ROTATION_SECONDS = 900 

def derive_key_pair(seed_bytes, counter):
    """
    Derives the private and public key for a specific time counter.
    Returns: (private_key_bytes_32, public_key_x_bytes_28)
    """
    # 1. Derivation: SHA256(seed || counter_BE)
    message = seed_bytes + struct.pack('>I', counter)
    digest = hashlib.sha256(message).digest()
    
    # 2. Use first 28 bytes as private scalar (simplification matching firmware uECC P-224)
    private_value = int.from_bytes(digest[:28], byteorder='big')
    
    # 3. Create private key object
    private_key = ec.derive_private_key(private_value, ec.SECP224R1())
    
    # 4. Get public key X coordinate
    public_numbers = private_key.public_key().public_numbers()
    x_bytes = public_numbers.x.to_bytes(28, byteorder='big') # P-224 X is 28 bytes
    
    # Private key as 32 bytes (standard format often used, padded) or 28 bytes? 
    # OpenHaystack often expects Base64 of the private scalar.
    # We'll return the 28-byte scalar padded to 32 bytes or just the 28 bytes depending on what's needed.
    # Let's keep the raw 28 bytes from the hash for clarity, but standard tools might surely want 32?
    # Actually P-224 private key is 28 bytes (224 bits). 
    private_key_bytes = digest[:28]
    
    return private_key_bytes, x_bytes

def get_hashed_adv_key(public_key_bytes):
    """
    Returns the SHA256 hash of the public key (used for FindMy query).
    """
    # Apple's "Hashed Advertisement Key" is often SHA256(Public_Key_X)
    return hashlib.sha256(public_key_bytes).digest()


def read_seed_from_main(main_c_path):
    """
    Parses main.c to extract the m_master_key_seed array.
    """
    try:
        if not os.path.exists(main_c_path):
            return None
            
        with open(main_c_path, 'r', encoding='utf-8') as f:
            content = f.read()
            
        # Regex to find the array content inside { ... }
        # static const uint8_t m_master_key_seed[32] = { ... };
        pattern = r"static\s+const\s+uint8_t\s+m_master_key_seed\[32\]\s*=\s*\{([^}]+)\};"
        match = re.search(pattern, content, re.DOTALL)
        
        if match:
            # Extract hex values
            hex_str = match.group(1)
            # Remove comments, newlines, 0x, commas
            cleaned = re.sub(r'0x|,|\s', '', hex_str)
            return bytes.fromhex(cleaned)
    except Exception as e:
        print(f"Warning: Could not read seed from main.c: {e}")
    return None


def main():
    parser = argparse.ArgumentParser(description='Export FindMy Keys from Master Seed')
    parser.add_argument('--seed', help='Master Seed in Hex (optional if main.c is present)')
    parser.add_argument('--main-c', default='../main.c', help='Path to main.c to read seed from (default: ../main.c)')
    parser.add_argument('--hours', type=int, default=24, help='Number of hours to generate keys for (default: 24)')
    parser.add_argument('--start-offset', type=int, default=0, help='Start generation N hours from now (negative for past)')
    parser.add_argument('--json', action='store_true', help='Output in standard JSON list format')
    parser.add_argument('--macless-json', action='store_true', help='Output in Macless-Haystack JSON format')
    parser.add_argument('--device-name', default="MyDevice", help='Device name for Macless JSON (default: MyDevice)')
    args = parser.parse_args()

    seed_bytes = None

    # 1. Try command line argument
    if args.seed:
        try:
            seed_bytes = bytes.fromhex(args.seed)
        except ValueError:
            print("Error: Invalid Hex Seed provided via --seed")
            return

    # 2. Try reading from main.c
    if seed_bytes is None:
        # Resolve relative path based on script location
        script_dir = os.path.dirname(os.path.abspath(__file__))
        target_main_c = os.path.join(script_dir, args.main_c)
        
        # Only print info if not outputting JSON to keep stdout clean for piping
        if not args.json and not args.macless_json:
            print(f"[Info] Attempting to read seed from: {target_main_c}")
            
        seed_bytes = read_seed_from_main(target_main_c)
        
        if seed_bytes:
            if not args.json and not args.macless_json:
                print(f"[Info] Found Seed: {seed_bytes.hex()}")
        else:
            print("Error: Could not find seed in main.c and no --seed provided.")
            print("Please ensure main.c has been configured using generate_seed.py first.")
            return

    now = int(time.time())
    start_time = now + (args.start_offset * 3600)
    
    num_intervals = (args.hours * 3600) // ROTATION_SECONDS
    
    # Prepare Macless format containers
    macless_additional_keys = []
    macless_additional_hashed_adv_keys = []
    first_priv_b64 = None
    first_hashed_pub_b64 = None
    
    standard_output_list = []
    
    if not args.json and not args.macless_json:
        print("-" * 80)
        print(f"{'Counter':<8} | {'Public Key (Base64)':<45} | {'Hashed Adv Key (Base64)':<45}")
        print("-" * 80)

    for i in range(num_intervals):
        priv, pub = derive_key_pair(seed_bytes, i)
        hashed_pub = get_hashed_adv_key(pub)
        
        pub_b64 = binascii.b2a_base64(pub).decode().strip()
        hashed_pub_b64 = binascii.b2a_base64(hashed_pub).decode().strip()
        priv_b64 = binascii.b2a_base64(priv).decode().strip()
        
        # Save first key pair for main object properties
        if i == 0:
            first_priv_b64 = priv_b64
            first_hashed_pub_b64 = hashed_pub_b64
        else:
            # Add subsequent keys to arrays for Macless format
            macless_additional_keys.append(priv_b64)
            macless_additional_hashed_adv_keys.append(hashed_pub_b64)
        
        item = {
            "counter": i,
            "privateKey": priv_b64,
            "publicKey": pub_b64,
            "hashedAdvKey": hashed_pub_b64
        }
        standard_output_list.append(item)
        
        if not args.json and not args.macless_json:
            print(f"{i:<8} | {pub_b64:<45} | {hashed_pub_b64:<45}")

    if args.macless_json:
        # Construct Macless-Haystack JSON object
        macless_obj = [{
            "id": args.device_name,
            "colorComponents": [0, 1, 0, 1],
            "name": args.device_name,
            "privateKey": first_priv_b64,
            "hashedAdvKey": first_hashed_pub_b64,
            "icon": "",
            "isActive": True,
            "additionalKeys": macless_additional_keys,
            "additionalHashedAdvKeys": macless_additional_hashed_adv_keys
        }]
        print(json.dumps(macless_obj, indent=None)) # Compact JSON typically preferred but indent=None is default
        
    elif args.json:
        print(json.dumps(standard_output_list, indent=2))
        
    elif not args.json:
        print("-" * 80)
        print("Usage:")
        print("1. 'Public Key' or 'Hashed Adv Key' is used to QUERY Apple's server.")
        print("2. 'Private Key' (in the JSON output) is used to DECRYPT the reports.")
        print("3. Use --macless-json to output in format compatible with existing fetching tools.")

if __name__ == "__main__":
    main()
