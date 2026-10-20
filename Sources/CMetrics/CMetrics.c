#include "CMetrics.h"
#include <mach/mach.h>
#include <sys/sysctl.h>
#include <sys/resource.h>
#include <libproc.h>
#include <stdlib.h>
#include <signal.h>
#include <unistd.h>

MPCPU mp_cpu(void) {
    host_cpu_load_info_data_t info = {0};
    mach_msg_type_number_t count = HOST_CPU_LOAD_INFO_COUNT;
    mach_port_t host = mach_host_self();
    kern_return_t result = host_statistics(host, HOST_CPU_LOAD_INFO, (host_info_t)&info, &count);
    mach_port_deallocate(mach_task_self(), host);
    MPCPU out = {0};
    if (result == KERN_SUCCESS) {
        out.active = (uint64_t)info.cpu_ticks[CPU_STATE_USER] +
            info.cpu_ticks[CPU_STATE_SYSTEM] + info.cpu_ticks[CPU_STATE_NICE];
        out.idle = info.cpu_ticks[CPU_STATE_IDLE];
        out.valid = 1;
    }
    return out;
}

MPMemory mp_memory(void) {
    vm_statistics64_data_t vm = {0};
    mach_msg_type_number_t count = HOST_VM_INFO64_COUNT;
    mach_port_t host = mach_host_self();
    vm_size_t page = 0;
    MPMemory out = {0};
    size_t size = sizeof(out.total);
    if (sysctlbyname("hw.memsize", &out.total, &size, NULL, 0) == 0 &&
        host_page_size(host, &page) == KERN_SUCCESS &&
        host_statistics64(host, HOST_VM_INFO64, (host_info64_t)&vm, &count) == KERN_SUCCESS) {
        uint64_t occupied = (uint64_t)vm.active_count + vm.inactive_count +
            vm.wire_count + vm.compressor_page_count;
        uint64_t reclaimable = (uint64_t)vm.purgeable_count + vm.external_page_count;
        out.used = (occupied > reclaimable ? occupied - reclaimable : 0) * page;
        if (out.used > out.total) out.used = out.total;
        out.valid = 1;
    }
    mach_port_deallocate(mach_task_self(), host);
    return out;
}

static pid_t *list_pids(int *count) {
    int capacity = proc_listallpids(NULL, 0) + 512;
    if (capacity <= 512) return NULL;
    pid_t *pids = calloc((size_t)capacity, sizeof(pid_t));
    if (!pids) return NULL;
    int n = proc_listallpids(pids, capacity * (int)sizeof(pid_t));
    *count = n > capacity ? capacity : n;
    return pids;
}

int mp_signal_session(int32_t session, int signal_number) {
    if (session <= 1 || session == getsid(0)) return 0;
    int count = 0, signalled = 0;
    pid_t *pids = list_pids(&count);
    if (!pids) return 0;
    for (int i = 0; i < count; i++) {
        if (pids[i] > 1 && pids[i] != session && getsid(pids[i]) == session) {
            if (kill(pids[i], signal_number) == 0) signalled++;
        }
    }
    // The caller lets the PTY owner terminate and reap its direct shell child.
    free(pids);
    return signalled;
}
