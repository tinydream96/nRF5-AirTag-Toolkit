#ifndef KEY_GENERATOR_H
#define KEY_GENERATOR_H

#include <stdint.h>

/* Defines the standard rotation interval in seconds (default 900s = 15m) */
#define KEY_ROTATION_SECONDS 900

/* Initialize the key generator with a 32-byte master seed */
void keygen_init(const uint8_t *seed_32b);

/* 
 * Calculate the derived public key for a specific time interval.
 * 
 * time_counter: Current unix timestamp / KEY_ROTATION_SECONDS
 * out_public_key_x: Buffer to store the 28-byte X-coordinate of the public key
 */
void keygen_get_key(uint32_t time_counter, uint8_t *out_public_key_x);

#endif
