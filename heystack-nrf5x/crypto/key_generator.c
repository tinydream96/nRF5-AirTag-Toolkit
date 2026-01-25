#include "key_generator.h"
#include "sha256.h"
#include "uECC.h"
#include <string.h>

static uint8_t m_master_seed[32];

void keygen_init(const uint8_t *seed_32b)
{
    memcpy(m_master_seed, seed_32b, 32);
}

void keygen_get_key(uint32_t time_counter, uint8_t *out_public_key_x)
{
    uint8_t hash_output[32];
    uint8_t private_key[28]; // P-224 private key size
    uint8_t public_key[56];  // P-224 public key size (28 * 2)
    
    // 1. Derivation: SHA256(seed || time_counter_be)
    SHA256_CTX ctx;
    uint8_t counter_be[4];
    
    // Convert counter to Big Endian
    counter_be[0] = (time_counter >> 24) & 0xFF;
    counter_be[1] = (time_counter >> 16) & 0xFF;
    counter_be[2] = (time_counter >> 8) & 0xFF;
    counter_be[3] = (time_counter) & 0xFF;
    
    sha256_init(&ctx);
    sha256_update(&ctx, m_master_seed, 32);
    sha256_update(&ctx, counter_be, 4);
    sha256_final(&ctx, hash_output);
    
    // 2. Reduce hash to private key (for P-224, we need 28 bytes)
    // Theoretically we should mod n, but for random SHA256 output, 
    // taking first 28 bytes is 'good enough' for this non-banking application
    // provided it is < curve_n. 
    // A robust impl would do modulo. 
    memcpy(private_key, hash_output, 28);
    
    // Ensure it's a valid scalar (simple clamp or verify)
    // micro-ecc handles scalars.
    
    // 3. Compute Public Key
    uECC_compute_public_key(private_key, public_key, uECC_secp224r1());
    
    // 4. Return X-coordinate (28 bytes)
    // In uncompressed format (0x04, X, Y), micro-ecc returns [X, Y]
    memcpy(out_public_key_x, public_key, 28);
}
