#ifndef PROFILE_TIMER_H
#define PROFILE_TIMER_H

#include <stdint.h>

#include "../code/app_config.h"

typedef enum {
    SWEEP_PROFILE_SECTION_POINT_TOTAL = 0,
    SWEEP_PROFILE_SECTION_SET_LO1,
    SWEEP_PROFILE_SECTION_WAIT_LOCK,
    SWEEP_PROFILE_SECTION_DMA_RESET,
    SWEEP_PROFILE_SECTION_DMA_START,
    SWEEP_PROFILE_SECTION_DMA_WAIT,
    SWEEP_PROFILE_SECTION_ACCUMULATE,
    SWEEP_PROFILE_SECTION_MEASURE,
    SWEEP_PROFILE_SECTION_EMIT_UART,
    SWEEP_PROFILE_SECTION_COUNT
} sweep_profile_section_t;

#if SWEEP_PROFILE_ENABLE

void sweep_profile_reset(uint8_t rbw_mode);
void sweep_profile_set_rbw_mode(uint8_t rbw_mode);
void sweep_profile_begin(sweep_profile_section_t section);
void sweep_profile_end(sweep_profile_section_t section);
void sweep_profile_note_point(void);
void sweep_profile_note_dma_rearm(void);
int sweep_profile_build_payload(unsigned char *dst,
                                unsigned short max_len,
                                unsigned short *out_len);

#else

#define sweep_profile_reset(rbw_mode)       ((void)0)
#define sweep_profile_set_rbw_mode(mode)    ((void)0)
#define sweep_profile_begin(section)        ((void)0)
#define sweep_profile_end(section)          ((void)0)
#define sweep_profile_note_point()          ((void)0)
#define sweep_profile_note_dma_rearm()      ((void)0)

int sweep_profile_build_payload(unsigned char *dst,
                                unsigned short max_len,
                                unsigned short *out_len);

#endif

#endif
