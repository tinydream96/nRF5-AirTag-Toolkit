/**
 * Copyright (c) 2015 - 2019, Nordic Semiconductor ASA
 *
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without modification,
 * are permitted provided that the following conditions are met:
 *
 * 1. Redistributions of source code must retain the above copyright notice, this
 *    list of conditions and the following disclaimer.
 *
 * 2. Redistributions in binary form, except as embedded into a Nordic
 *    Semiconductor ASA integrated circuit in a product or a software update for
 *    such product, must reproduce the above copyright notice, this list of
 *    conditions and the following disclaimer in the documentation and/or other
 *    materials provided with the distribution.
 *
 * 3. Neither the name of Nordic Semiconductor ASA nor the names of its
 *    contributors may be used to endorse or promote products derived from this
 *    software without specific prior written permission.
 *
 * 4. This software, with or without modification, must only be used with a
 *    Nordic Semiconductor ASA integrated circuit.
 *
 * 5. Any software provided in binary form under this license must not be reverse
 *    engineered, decompiled, modified and/or disassembled.
 *
 * THIS SOFTWARE IS PROVIDED BY NORDIC SEMICONDUCTOR ASA "AS IS" AND ANY EXPRESS
 * OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
 * OF MERCHANTABILITY, NONINFRINGEMENT, AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL NORDIC SEMICONDUCTOR ASA OR CONTRIBUTORS BE
 * LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE
 * GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT
 * OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 *
 */
/**
 * @brief Blinky Sample Application main file.
 *
 * This file contains the source code for a sample server application using the LED Button service.
 */

#include <stdint.h>
#include <string.h>
#include "nordic_common.h"
#include "nrf.h"
#include "app_error.h"
#include "boards.h"
#include "app_timer.h"
#include "app_button.h"
#include "main.h"
#include "math.h"
// #include "key_generator.h"

#if defined(BATTERY_LEVEL) && BATTERY_LEVEL == 1
#if NRF_SDK_VERSION < 15
#include "libraries/eddystone/es_battery_voltage.h"
#else
#include "ble/ble_services/eddystone/es_battery_voltage.h"
#endif
#endif

#if defined(DYNAMIC_KEYS) && DYNAMIC_KEYS == 1
#include "key_generator.h"

// Master Seed (32 bytes). In a real deployment, this should be written to UICR or verify-protected generic flash.
// For this PoC, we default to a known seed.
static const uint8_t m_master_key_seed[32] = "LinkyTagDynamicSeedPlaceholder!!";
#else
// Legacy Static Keys
// This string is searched by the patch script
static const char * key_placeholder __attribute__((used)) = "OFFLINEFINDINGPUBLICKEYHERE!";

// Buffer to hold keys after patching
// MAX_KEYS should be large enough, or we can use the size of the keyfile
#ifndef MAX_KEYS
#define MAX_KEYS 50 // Default backup
#endif

// We need a buffer to store the keys. The patch script writes binary data here.
// The public keys are 28 bytes each.
// NOTE: In the original implementation, the keys were likely in a flat array.
// We declare a large enough buffer. ensuring alignment.
// Using a large array of uint8_t.
// 28 bytes * MAX_KEYS + padding for safety (keyfile might be larger or contain metadata)
static const uint8_t m_public_keys[28 * MAX_KEYS + 1024] = "OFFLINEFINDINGPUBLICKEYHERE!";
#endif

static uint32_t m_current_time_counter = 0;

// Define timer ID variable
APP_TIMER_DEF(m_key_change_timer_id);

// Timer interval definition
// Default to 15 minutes (900 seconds) if not defined
#ifndef KEY_ROTATION_INTERVAL
#define KEY_ROTATION_INTERVAL 900
#endif

#define TIMER_INTERVAL COMPAT_APP_TIMER_TICKS(KEY_ROTATION_INTERVAL * 1000)

#if defined(BATTERY_LEVEL) && BATTERY_LEVEL == 1
#define BATTERY_VOLTAGE_MIN (1800.0)
#define BATTERY_VOLTAGE_MAX (3300.0)
#define ROTATION_PER_DAY ((24 * 60 * 60) / KEY_ROTATION_INTERVAL)

uint8_t read_nrf_battery_voltage_percent(void)
{
    uint16_t real_vbatt;
    es_battery_voltage_get(&real_vbatt);

    uint16_t vbatt = MIN(real_vbatt, BATTERY_VOLTAGE_MAX);
    vbatt = (vbatt - BATTERY_VOLTAGE_MIN) / (BATTERY_VOLTAGE_MAX - BATTERY_VOLTAGE_MIN) * 100;

    COMPAT_NRF_LOG_INFO("Battery voltage: %d mV, %d%% (min: %d mV, max: %d mV)", real_vbatt, vbatt, BATTERY_VOLTAGE_MIN, BATTERY_VOLTAGE_MAX);

    return vbatt;
}

void update_battery_level(void)
{
    static uint32_t rotation = 0;

    if (rotation == 0) {
        COMPAT_NRF_LOG_INFO("Updating battery level: %d / %d", rotation, ROTATION_PER_DAY);
        uint8_t battery_level = read_nrf_battery_voltage_percent();
        set_battery(battery_level);
    } else {
        COMPAT_NRF_LOG_INFO("Skipping battery level update: %d / %d", rotation, ROTATION_PER_DAY);
    }

    rotation = (rotation + 1) % ROTATION_PER_DAY;
}
#endif

#ifdef HAS_RADIO_PA
static void pa_lna_assist(uint32_t gpio_pa_pin, uint32_t gpio_lna_pin)
{
    ret_code_t err_code;

    static const uint32_t gpio_toggle_ch = 0;
    static const uint32_t ppi_set_ch = 0;
    static const uint32_t ppi_clr_ch = 1;

    // Configure SoftDevice PA/LNA assist
    ble_opt_t opt;
    memset(&opt, 0, sizeof(ble_opt_t));
    // Common PA/LNA config
    opt.common_opt.pa_lna.gpiote_ch_id  = gpio_toggle_ch;        // GPIOTE channel
    opt.common_opt.pa_lna.ppi_ch_id_clr = ppi_clr_ch;            // PPI channel for pin clearing
    opt.common_opt.pa_lna.ppi_ch_id_set = ppi_set_ch;            // PPI channel for pin setting
    // PA config
    opt.common_opt.pa_lna.pa_cfg.active_high = 1;                // Set the pin to be active high
    opt.common_opt.pa_lna.pa_cfg.enable      = 1;                // Enable toggling
    opt.common_opt.pa_lna.pa_cfg.gpio_pin    = gpio_pa_pin;      // The GPIO pin to toggle

    // LNA config
    opt.common_opt.pa_lna.lna_cfg.active_high  = 1;              // Set the pin to be active high
    opt.common_opt.pa_lna.lna_cfg.enable       = 1;              // Enable toggling
    opt.common_opt.pa_lna.lna_cfg.gpio_pin     = gpio_lna_pin;   // The GPIO pin to toggle

    err_code = sd_ble_opt_set(BLE_COMMON_OPT_PA_LNA, &opt);
    APP_ERROR_CHECK(err_code);
    COMPAT_NRF_LOG_INFO("PA/LNA assist enabled on pins: PA=%d, LNA=%d", gpio_pa_pin, gpio_lna_pin);
}
#endif

void set_and_advertise_next_key(void *p_context)
{
    uint8_t public_key_28b[28];
    
#if defined(DYNAMIC_KEYS) && DYNAMIC_KEYS == 1
    // Generate the next key based on the current counter
    keygen_get_key(m_current_time_counter, public_key_28b);
#else
    // Legacy Static Keys
    // key_placeholder is just to ensure string exists in binary for patching.
    // The actual keys are patched into m_public_keys (or wherever the patch script targets).
    // CAUTION: The original patch script "stflash-*-patched" uses `grep` to find "OFFLINEFINDINGPUBLICKEYHERE!"
    // and then `dd` to write `ADV_KEYS_FILE` content to that location.
    // So `m_public_keys` MUST be initialized with `OFFLINEFINDINGPUBLICKEYHERE!` or be placed exactly where 
    // the string is.
    // BUT, the string is 28 chars. A real key file is much larger. 
    // We need to ensure `m_public_keys` is what holds the pattern initially.
    
    // We can't just define a char* pointer, we need the actual storage.
    // Let's copy from m_public_keys which should have been patched.
    
    // Safety check: key usage wrap around
    uint32_t key_index = m_current_time_counter % MAX_KEYS;
    
    // Note: This relies on the fact that m_public_keys has been patched with the binary content of the keyfile.
    // If it hasn't (e.g. running unpatched), we'll read zeros or garbage.
    
    // Wait, the patch script replaces the STRING "OFFLINEFINDINGPUBLICKEYHERE!".
    // We need `m_public_keys` to contain that string to be found.
    // And it must be large enough to hold all the keys.
    // C doesn't easily allow "Array of 2000 bytes starting with specific string".
    // 
    // Hack: Initialize the start of the array with the pattern.
    // "OFFLINEFINDINGPUBLICKEYHERE!" is 28 chars + null.
    // 28 bytes is exactly one key size (without the type/len byte which are handled by stack?).
    // Wait, standard keys are 28 bytes (X coord).
    // So the placeholder is exactly 28 bytes.
    // 
    // The previous implementation likely did something like:
    // static uint8_t m_public_keys[] = "OFFLINEFINDINGPUBLICKEYHERE!....................";
    // 
    // Let's try to mimic that.
    
    // Copy the key from the global array
    memcpy(public_key_28b, &m_public_keys[key_index * 28], 28);
#endif

    #if defined(BATTERY_LEVEL) && BATTERY_LEVEL == 1
        update_battery_level();
    #endif

    // Set key to be advertised
    // NOTE: ble_set_advertisement_key implementation expects a char* buffer for copying data.
    // Ensure ble_stack.c handles raw bytes correctly. Since the original implementation passed public_key[i] which was char[28],
    // passing uint8_t* cast to char* is compatible.
    ble_set_advertisement_key((const char *)public_key_28b);
    
    COMPAT_NRF_LOG_INFO("Rotating key | Counter: %d", m_current_time_counter);
    
    // Increment counter for next time
    m_current_time_counter++;
}

void assert_nrf_callback(uint16_t line_num, const uint8_t * p_file_name)
{
    app_error_handler(0xDEADBEEF, line_num, p_file_name);
}

static void timers_init(void)
{
    // Initialize timer module, making it use the scheduler
    #if NRF_SDK_VERSION < 15
        APP_TIMER_INIT(APP_TIMER_PRESCALER, APP_TIMER_OP_QUEUE_SIZE, NULL);
    #else
        int err_code = app_timer_init();
        APP_ERROR_CHECK(err_code);
    #endif
}

void ble_stack_init(void)
{
    ret_code_t err_code;

    #if NRF_SDK_VERSION >= 15
        err_code = nrf_sdh_enable_request();
        APP_ERROR_CHECK(err_code);

        uint32_t ram_start = 0;
        err_code = nrf_sdh_ble_default_cfg_set(APP_BLE_CONN_CFG_TAG, &ram_start);
        APP_ERROR_CHECK(err_code);

        err_code = nrf_sdh_ble_enable(&ram_start);
        APP_ERROR_CHECK(err_code);

    #else
        #define CENTRAL_LINK_COUNT 0
        #define PERIPHERAL_LINK_COUNT 1
        #define BLE_UUID_VS_COUNT_MIN 1

        nrf_clock_lf_cfg_t clock_lf_cfg = NRF_CLOCK_LFCLKSRC;

        SOFTDEVICE_HANDLER_INIT(&clock_lf_cfg, NULL);

        ble_enable_params_t ble_enable_params;
        err_code = softdevice_enable_get_default_config(CENTRAL_LINK_COUNT,
                                                        PERIPHERAL_LINK_COUNT,
                                                        &ble_enable_params);
        APP_ERROR_CHECK(err_code);

        ble_enable_params.common_enable_params.vs_uuid_count = BLE_UUID_VS_COUNT_MIN;
        CHECK_RAM_START_ADDR(CENTRAL_LINK_COUNT, PERIPHERAL_LINK_COUNT);

        err_code = softdevice_enable(&ble_enable_params);
        APP_ERROR_CHECK(err_code);
    #endif
}


static void log_init(void)
{
#if defined(HAS_DEBUG) && HAS_DEBUG == 1
    ret_code_t err_code = NRF_LOG_INIT(NULL);
    APP_ERROR_CHECK(err_code);

#if NRF_SDK_VERSION >= 15
    NRF_LOG_DEFAULT_BACKENDS_INIT();
#else
#endif
#endif
}

static void power_management_init(void)
{
    #if NRF_SDK_VERSION >= 15
        ret_code_t err_code;
        err_code = nrf_pwr_mgmt_init();
        APP_ERROR_CHECK(err_code);
    #else
    #endif
}

static void idle_state_handle(void)
{
    if (NRF_LOG_PROCESS() == false)
    {
        #if NRF_SDK_VERSION >= 15
        nrf_pwr_mgmt_run();
        #else
        APP_ERROR_CHECK(sd_app_evt_wait());
        #endif
    }
}

static void timer_config(void)
{
    uint32_t err_code;

    err_code = app_timer_create(&m_key_change_timer_id, APP_TIMER_MODE_REPEATED, set_and_advertise_next_key);
    APP_ERROR_CHECK(err_code);

    err_code = app_timer_start(m_key_change_timer_id, TIMER_INTERVAL, NULL);
    APP_ERROR_CHECK(err_code);
}


int main(void)
{
    // Initialize
    log_init();

    #if defined(BATTERY_LEVEL) && BATTERY_LEVEL == 1
        es_battery_voltage_init();
    #endif
    
    #if defined(DYNAMIC_KEYS) && DYNAMIC_KEYS == 1
    // Initialize Crypto Engine
    keygen_init(m_master_key_seed);

    COMPAT_NRF_LOG_INFO("Dynamic Key Generation Enabled");
    #else
    COMPAT_NRF_LOG_INFO("Legacy Static Key Mode");
    // Ensure the variable is used to avoid optimization
    if (m_public_keys[0] == 0) {
        COMPAT_NRF_LOG_INFO("Keys uninitialized");
    }
    #endif

    COMPAT_NRF_LOG_INFO("Rotation Interval: %d seconds", KEY_ROTATION_INTERVAL);

    // Initialize the timer module
    timers_init();
    
    // Always configure timer for dynamic rotation
    timer_config();

    // Initialize the power management module
    power_management_init();

    // Initialize the BLE stack
    ble_stack_init();

    // Initialize advertising
    ble_advertising_init();

#ifdef HAS_RADIO_PA
    // Configure the PA/LNA
    pa_lna_assist(GPIO_PA_PIN, GPIO_LNA_PIN);
#endif

#ifdef HAS_DCDC
    // Enable DC/DC converter
    COMPAT_NRF_LOG_INFO("Enabling DC/DC converter");
    uint32_t err_code = sd_power_dcdc_mode_set(NRF_POWER_DCDC_ENABLE);
    APP_ERROR_CHECK(err_code);
#endif

    COMPAT_NRF_LOG_INFO("Starting advertising");

    // Start with a placeholder key or just start timer to set it immediately?
    // Doing the heavy calculation (ECC) in main() before the loop is fine, but if it takes too long (>2-3s),
    // the watchdog might trigger (if enabled) or SoftDevice might complain if already enabled.
    // Here we calculate it ONCE before entering the loop.
    
    // NOTE: Generating P-224 key takes ~1 second on nRF52.
    set_and_advertise_next_key(NULL);

    // Enter main loop
    for (;;)
    {
        idle_state_handle();
    }
}


/**
 * @}
 */
