import matplotlib.pyplot as plt
import os

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
LOG_FILE_PATH = os.path.join(SCRIPT_DIR, '../reports/sim_log.txt')
OUTPUT_IMAGE = os.path.join(SCRIPT_DIR, '../reports/graph_3_analytics.png')

def main():
    if not os.path.exists(LOG_FILE_PATH):
        print(f"Error: {LOG_FILE_PATH} not found.")
        return

    sys_cores = []
    task_host = {}
    task_first_alloc = {}

    with open(LOG_FILE_PATH, 'r') as file:
        for line in file:
            if "LOG_SYS" in line:
                _, _, c, _ = line.strip().split(',')
                sys_cores.append(int(c))
            elif "LOG_HOST" in line:
                _, t, tid, _, _ = line.strip().split(',')
                task_host[int(tid)] = float(t)
            elif "LOG_ALLOC" in line:
                _, t, tid, _ = line.strip().split(',')
                tid = int(tid)
                if tid not in task_first_alloc:
                    task_first_alloc[tid] = float(t)

    fig, (ax1, ax2) = plt.subplots(1, 2, figsize=(14, 6))

    # Subplot A: Bottleneck Pie Chart
    idle_c = sum(1 for c in sys_cores if c == 0)
    sat_c  = sum(1 for c in sys_cores if c == 64)
    act_c  = len(sys_cores) - idle_c - sat_c

    labels = ['Idle (0 Cores)', 'Active (1-63 Cores)', 'Saturated (64 Cores)']
    sizes = [idle_c, act_c, sat_c]
    colors = ['#c7c7c7', '#2ca02c', '#d62728']
    
    # Filter out empty slices to prevent errors
    filtered_data = [(sz, l, c) for sz, l, c in zip(sizes, labels, colors) if sz > 0]
    sizes, labels, colors = zip(*filtered_data) if filtered_data else ([], [], [])

    if sizes:
        ax1.pie(sizes, labels=labels, colors=colors, autopct='%1.1f%%', startangle=140, 
                wedgeprops={'edgecolor': 'black'})
    ax1.set_title('System Core States', fontweight='bold')

    # Subplot B: Latency Histogram
    latencies = [task_first_alloc[tid] - host_time for tid, host_time in task_host.items() if tid in task_first_alloc]

    if latencies:
        ax2.hist(latencies, bins=10, color='#ff7f0e', edgecolor='black', alpha=0.8)
        ax2.set_title('Task Start Latency Distribution', fontweight='bold')
        ax2.set_xlabel('Wait Time (ns)')
        ax2.set_ylabel('Number of Tasks')
        ax2.grid(axis='y', linestyle='--', alpha=0.7)

    plt.tight_layout()
    plt.savefig(OUTPUT_IMAGE, dpi=300)
    print(f"Saved: {os.path.abspath(OUTPUT_IMAGE)}")

if __name__ == '__main__':
    main()
