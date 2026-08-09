#ifndef TEST_SLEEP_H
#define TEST_SLEEP_H

#include <stdint.h>

static inline int usleep(uint32_t usec)
{
    (void)usec;
    return 0;
}

#endif
