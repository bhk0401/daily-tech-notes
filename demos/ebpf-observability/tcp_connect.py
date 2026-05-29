#!/usr/bin/env python3
"""
tcp_connect.py - 使用 bcc 追踪 TCP 连接
使用方法：sudo python3 tcp_connect.py [pid]
"""

from bcc import BPF
import argparse

parser = argparse.ArgumentParser(description="Trace TCP connections")
parser.add_argument("-p", "--pid", type=int, help="Trace this PID only")
args = parser.parse_args()

bpf_text = """
#include <uapi/linux/ptrace.h>
#include <net/net_namespace.h>
#include <net/sock.h>
#include <linux/tcp.h>

BPF_PERF_OUTPUT(events);

struct event_t {
    u32 pid;
    u64 ip;
    char saddr[16];
    char daddr[16];
    u16 dport;
    char comm[TASK_COMM_LEN];
};

int trace_tcp_connect(struct pt_regs *ctx) {
    struct sock *sk = (struct sock *)PT_REGS_PARM1(ctx);
    if (sk == NULL)
        return 0;

    struct event_t event = {};
    event.pid = bpf_get_current_pid_tgid() >> 32;
    
    // Filter by PID if specified
    FILTER_PID

    bpf_get_current_comm(&event.comm, sizeof(event.comm));
    
    // Extract IP and port info (simplified)
    u16 family = sk->__sk_common.skc_family;
    event.ip = family;
    
    events.perf_submit(ctx, &event, sizeof(event));
    return 0;
}
"""

if args.pid:
    bpf_text = bpf_text.replace("FILTER_PID", f"if (event.pid != {args.pid}) return 0;")
else:
    bpf_text = bpf_text.replace("FILTER_PID", "")

b = BPF(text=bpf_text)
b.attach_kprobe(event="tcp_connect", fn_name="trace_tcp_connect")

print("Tracing TCP connections... Ctrl+C to stop")
print("%-8s %-16s %-6s %-16s %-16s %-6s" % ("PID", "COMM", "IP", "SADDR", "DADDR", "DPORT"))

def print_event(cpu, data, size):
    event = b["events"].event(data)
    print("%-8s %-16s %-6s %-16s %-16s %-6s" % (
        event.pid, event.comm.decode(), 
        "v4" if event.ip == 2 else "v6",
        event.saddr.decode() if event.saddr else "0.0.0.0",
        event.daddr.decode() if event.daddr else "0.0.0.0",
        event.dport
    ))

b["events"].open_perf_buffer(print_event)
while True:
    try:
        b.perf_buffer_poll()
    except KeyboardInterrupt:
        exit()
