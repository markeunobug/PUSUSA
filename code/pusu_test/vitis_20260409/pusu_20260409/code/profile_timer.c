#include "../code/profile_timer.h"

#include <string.h>

#include "xtime_l.h"

#define SWEEP_PROFILE_VERSION 1U

typedef struct {
    uint32_t count;
    uint64_t total_ticks;
    uint64_t min_ticks;
    uint64_t max_ticks;
} sweep_profile_section_stats_t;

typedef struct {
    uint8_t enabled;
    uint8_t rbw_mode;
    uint32_t sweep_count;
    uint32_t point_count;
    uint32_t dma_rearm_count;
    sweep_profile_section_stats_t sections[SWEEP_PROFILE_SECTION_COUNT];
#if SWEEP_PROFILE_ENABLE
    uint64_t active_start[SWEEP_PROFILE_SECTION_COUNT];
    uint8_t active[SWEEP_PROFILE_SECTION_COUNT];
#endif
} sweep_profile_state_t;

static sweep_profile_state_t g_sweep_profile;

static void write_u16_be(unsigned char *dst, uint16_t value);
static void write_u32_be(unsigned char *dst, uint32_t value);
static void write_u64_be(unsigned char *dst, uint64_t value);

#if SWEEP_PROFILE_ENABLE

void sweep_profile_reset(uint8_t rbw_mode)
{
    memset(&g_sweep_profile, 0, sizeof(g_sweep_profile));
    g_sweep_profile.enabled = 1U;
    g_sweep_profile.rbw_mode = rbw_mode;
    g_sweep_profile.sweep_count = 1U;
}

void sweep_profile_set_rbw_mode(uint8_t rbw_mode)
{
    g_sweep_profile.enabled = 1U;
    g_sweep_profile.rbw_mode = rbw_mode;
}

void sweep_profile_begin(sweep_profile_section_t section)
{
    XTime now;

    if ((uint32_t)section >= (uint32_t)SWEEP_PROFILE_SECTION_COUNT) {
        return;
    }

    XTime_GetTime(&now);
    g_sweep_profile.active_start[section] = (uint64_t)now;
    g_sweep_profile.active[section] = 1U;
}

void sweep_profile_end(sweep_profile_section_t section)
{
    XTime now;
    uint64_t elapsed;
    sweep_profile_section_stats_t *stats;

    if ((uint32_t)section >= (uint32_t)SWEEP_PROFILE_SECTION_COUNT) {
        return;
    }
    if (g_sweep_profile.active[section] == 0U) {
        return;
    }

    XTime_GetTime(&now);
    elapsed = (uint64_t)now - g_sweep_profile.active_start[section];
    stats = &g_sweep_profile.sections[section];
    stats->count++;
    stats->total_ticks += elapsed;
    if ((stats->count == 1U) || (elapsed < stats->min_ticks)) {
        stats->min_ticks = elapsed;
    }
    if (elapsed > stats->max_ticks) {
        stats->max_ticks = elapsed;
    }
    g_sweep_profile.active[section] = 0U;
}

void sweep_profile_note_point(void)
{
    g_sweep_profile.point_count++;
}

void sweep_profile_note_dma_rearm(void)
{
    g_sweep_profile.dma_rearm_count++;
}

#else

static void sweep_profile_init_disabled(void)
{
    memset(&g_sweep_profile, 0, sizeof(g_sweep_profile));
    g_sweep_profile.enabled = 0U;
}

#endif

int sweep_profile_build_payload(unsigned char *dst,
                                unsigned short max_len,
                                unsigned short *out_len)
{
    uint32_t i;
    unsigned int offset = 0U;
    const unsigned int header_len = 24U;
    const unsigned int section_len = 26U;
    const unsigned int total_len =
        header_len + (unsigned int)SWEEP_PROFILE_SECTION_COUNT * section_len;

    if ((dst == 0) || (out_len == 0) || (max_len < total_len)) {
        return -1;
    }

#if !SWEEP_PROFILE_ENABLE
    sweep_profile_init_disabled();
#endif

    dst[offset++] = SWEEP_PROFILE_VERSION;
    dst[offset++] = g_sweep_profile.enabled;
    dst[offset++] = g_sweep_profile.rbw_mode;
    dst[offset++] = 0U;
    write_u32_be(&dst[offset], (uint32_t)COUNTS_PER_SECOND);
    offset += 4U;
    write_u32_be(&dst[offset], g_sweep_profile.sweep_count);
    offset += 4U;
    write_u32_be(&dst[offset], g_sweep_profile.point_count);
    offset += 4U;
    write_u32_be(&dst[offset], g_sweep_profile.dma_rearm_count);
    offset += 4U;
    write_u16_be(&dst[offset], (uint16_t)SWEEP_PROFILE_SECTION_COUNT);
    offset += 2U;
    write_u16_be(&dst[offset], 0U);
    offset += 2U;

    for (i = 0U; i < (uint32_t)SWEEP_PROFILE_SECTION_COUNT; i++) {
        const sweep_profile_section_stats_t *stats = &g_sweep_profile.sections[i];

        dst[offset++] = (unsigned char)i;
        dst[offset++] = 0U;
        write_u32_be(&dst[offset], stats->count);
        offset += 4U;
        write_u64_be(&dst[offset], stats->total_ticks);
        offset += 8U;
        write_u64_be(&dst[offset], stats->min_ticks);
        offset += 8U;
        write_u64_be(&dst[offset], stats->max_ticks);
        offset += 8U;
    }

    *out_len = (unsigned short)offset;
    return 0;
}

static void write_u16_be(unsigned char *dst, uint16_t value)
{
    dst[0] = (unsigned char)((value >> 8) & 0xFFU);
    dst[1] = (unsigned char)(value & 0xFFU);
}

static void write_u32_be(unsigned char *dst, uint32_t value)
{
    dst[0] = (unsigned char)((value >> 24) & 0xFFU);
    dst[1] = (unsigned char)((value >> 16) & 0xFFU);
    dst[2] = (unsigned char)((value >> 8) & 0xFFU);
    dst[3] = (unsigned char)(value & 0xFFU);
}

static void write_u64_be(unsigned char *dst, uint64_t value)
{
    dst[0] = (unsigned char)((value >> 56) & 0xFFU);
    dst[1] = (unsigned char)((value >> 48) & 0xFFU);
    dst[2] = (unsigned char)((value >> 40) & 0xFFU);
    dst[3] = (unsigned char)((value >> 32) & 0xFFU);
    dst[4] = (unsigned char)((value >> 24) & 0xFFU);
    dst[5] = (unsigned char)((value >> 16) & 0xFFU);
    dst[6] = (unsigned char)((value >> 8) & 0xFFU);
    dst[7] = (unsigned char)(value & 0xFFU);
}
