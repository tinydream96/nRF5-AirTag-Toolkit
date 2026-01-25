#!/usr/bin/env python3
import sys
import base64
import hashlib
import argparse
import shutil
import os
import struct
import binascii
from string import Template
from cryptography.hazmat.primitives.asymmetric import ec
from cryptography.hazmat.backends import default_backend

# Logic from generate_seed.py / firmware
def derive_key(seed, counter):
    # Match firmware logic: SHA256(seed || counter_BE)
    message = seed + struct.pack('>I', counter)
    digest = hashlib.sha256(message).digest()
    
    # Use first 28 bytes as private key
    private_value = int.from_bytes(digest[:28], byteorder='big')
    
    # Create private key object
    private_key = ec.derive_private_key(private_value, ec.SECP224R1())
    
    # Get public key numbers
    public_numbers = private_key.public_key().public_numbers()
    x = public_numbers.x
    
    # X coordinate as 28 bytes
    x_bytes = x.to_bytes(28, byteorder='big')
    return private_value, x_bytes

def sha256(data):
    digest = hashlib.new("sha256")
    digest.update(data)
    return digest.digest()

def int_to_bytes(n, length):
    return n.to_bytes(length, 'big')

TEMPLATE = Template('{'
                    '"id": "$id",'
                    '"colorComponents": ['
                    '    0,'
                    '    1,'
                    '    0,'
                    '    1'
                    '],'
                    '"name": "$name",'
                    '"privateKey": "$privateKey",'
                    '"hashedAdvKey": "$hashedAdvKey",'
                    '"icon": "",'
                    '"isActive": true,'
                    '"additionalKeys": [$additionalKeys],'
                    '"additionalHashedAdvKeys": [$additionalHashedAdvKeys]'
                    '}')

def main():
    parser = argparse.ArgumentParser(description='Generate keys from existing seed')
    parser.add_argument('-s', '--seed', help='Seed in Hex format (64 chars)', required=True)
    parser.add_argument('-n', '--nkeys', help='number of keys to generate', type=int, default=50)
    parser.add_argument('-p', '--prefix', help='prefix of the keyfiles', required=True)
    parser.add_argument('-o', '--output', help='output folder', default='keys_from_seed/')
    
    args = parser.parse_args()
    
    seed_hex = args.seed
    if len(seed_hex) != 64:
        print("Error: Seed must be 32 bytes (64 hex characters)")
        sys.exit(1)
        
    try:
        seed_bytes = binascii.unhexlify(seed_hex)
    except:
        print("Error: Invalid hex string")
        sys.exit(1)

    OUTPUT_FOLDER = args.output
    if not os.path.exists(OUTPUT_FOLDER):
        os.makedirs(OUTPUT_FOLDER)
        
    prefix = args.prefix
    
    # 1. Binary Keyfile (for flashing? No, this script is for offline records, but we keep format)
    # The original generate_keys.py writes a binary file with [count][key1][key2]...
    # We replicate it just in case.
    keyfile = open(os.path.join(OUTPUT_FOLDER, prefix + '_keyfile'), 'wb')
    keyfile.write(struct.pack("B", args.nkeys))
    
    # 2. Devices JSON
    devices = open(os.path.join(OUTPUT_FOLDER, prefix + '_devices.json'), 'w')
    devices.write('[\n')
    
    # 3. .keys text file
    keys_txt = open(os.path.join(OUTPUT_FOLDER, prefix + '.keys'), 'w')
    
    additionalKeys = []
    additionalHashedAdvKeys = []
    
    print(f"Generating {args.nkeys} keys for {prefix} from seed...")
    
    for i in range(args.nkeys):
        priv_int, adv_bytes = derive_key(seed_bytes, i)
        
        priv_bytes = int_to_bytes(priv_int, 28) # 28 bytes private
        
        # Base64 encodings
        priv_b64 = base64.b64encode(priv_bytes).decode("ascii")
        adv_b64 = base64.b64encode(adv_bytes).decode("ascii")
        s256_b64 = base64.b64encode(sha256(adv_bytes)).decode("ascii")
        
        # Write to binary keyfile (just public key)
        keyfile.write(adv_bytes)
        
        # Check for '/' in hash (Mac-less approach skipped this, but we are replicating generate_keys logic?)
        # Actually generate_keys.py skips/regenerates if '/' is present.
        # BUT here we are DETERMINISTIC based on seed. We CANNOT skip.
        # If the firmware blindly generates, we must too.
        # The firmware does NOT skip. It just runs. So we should record what the firmware will use.
        
        # Store for JSON
        if i == 0:
            # First key is the main one
            main_priv = priv_b64
            main_adv_hash = s256_b64
        else:
            additionalKeys.append(priv_b64)
            additionalHashedAdvKeys.append(s256_b64)
            
        # Write to .keys
        keys_txt.write(f'Index: {i}\n')
        keys_txt.write(f'Private key: {priv_b64}\n')
        keys_txt.write(f'Advertisement key: {adv_b64}\n')
        keys_txt.write(f'Hashed adv key: {s256_b64}\n\n')

    # Format JSON arrays
    addKeysS = ''
    if additionalKeys:
        addKeysS = "\"" + "\",\"".join(additionalKeys) + "\""
        
    addHashedAdvKeysS = ''
    if additionalHashedAdvKeys:
        addHashedAdvKeysS = "\"" + "\",\"".join(additionalHashedAdvKeys) + "\""

    # Write JSON
    devices.write(TEMPLATE.substitute(name=prefix,
                                      id=prefix,
                                      privateKey=main_priv,
                                      hashedAdvKey=main_adv_hash,
                                      additionalKeys=addKeysS,
                                      additionalHashedAdvKeys=addHashedAdvKeysS
                                      ))
    devices.write(']')
    
    keyfile.close()
    devices.close()
    keys_txt.close()
    
    print(f"✅ Success! Output in {OUTPUT_FOLDER}")

if __name__ == "__main__":
    main()
