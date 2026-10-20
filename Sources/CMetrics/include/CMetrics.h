#pragma once
#include <stdint.h>
#include <stddef.h>

typedef struct { uint64_t active, idle; int valid; } MPCPU;
typedef struct { uint64_t used, total; int valid; } MPMemory;
MPCPU mp_cpu(void);
MPMemory mp_memory(void);
// Only processes still belonging to our terminal's session may be signalled.
int mp_signal_session(int32_t session, int signal_number);
