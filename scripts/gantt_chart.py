import matplotlib.pyplot as plt
import collections
import os

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
LOG_FILE_PATH = os.path.join(SCRIPT_DIR, '../reports/sim_log.txt')
OUTPUT_IMAGE = os.path.join(SCRIPT_DIR, '../reports/graph_2_gantt_chart.png')

def main():
    if not os.path.exists(LOG_FILE_PATH):
        print(f"Error: {LOG_FILE_PATH} not found.")
        return

    task_host = {}                                 
    task_exec = collections.defaultdict(list)      
    core_start = {}                                
    max_t = 0.0

    with open(LOG_FILE_PATH, 'r') as file:
        for line in file:
            if "LOG_SYS" in line:
                _, t, _, _ = line.strip().split(',')
                max_t = float(t)
            elif "LOG_HOST" in line:
                _, t, tid, _, _ = line.strip().split(',')
                task_host[int(tid)] = float(t)
            elif "LOG_ALLOC" in line:
                _, t, tid, cid = line.strip().split(',')
                core_start[int(cid)] = (float(t), int(tid))
            elif "LOG_FREE" in line:
                _, t, _, cid = line.strip().split(',')
                cid = int(cid)
                if cid in core_start:
                    start_t, alloc_tid = core_start[cid]
                    task_exec[alloc_tid].append((start_t, float(t) - start_t))
                    del core_start[cid]

    # Handle remaining
    for cid, (start_t, alloc_tid) in core_start.items():
        task_exec[alloc_tid].append((start_t, max_t - start_t))

    fig, ax = plt.subplots(figsize=(12, 8))
    y_ticks = []
    y_labels = []
    y_pos = 10

    # CHANGE: Only plot the first 60 tasks to prevent crowding!
    sorted_tids = sorted(task_host.keys())[:60]

    for tid in sorted_tids:
        host_t = task_host[tid]
        execs = task_exec[tid]
        
        if execs:
            first_alloc = min(e[0] for e in execs)
            # Red bar: Wait time in FIFO
            ax.broken_barh([(host_t, first_alloc - host_t)], (y_pos, 6), facecolors='#d62728', alpha=0.7, label='Pending' if tid==sorted_tids[0] else "")
            # Blue bars: Execution time on cores
            ax.broken_barh(execs, (y_pos, 6), facecolors='#1f77b4', alpha=0.9, label='Execution' if tid==sorted_tids[0] else "")
        else:
            ax.broken_barh([(host_t, max_t - host_t)], (y_pos, 6), facecolors='#d62728', alpha=0.7)
            
        y_ticks.append(y_pos + 3)
        y_labels.append(f'Task {tid}')
        y_pos += 10

    ax.set_yticks(y_ticks)
    ax.set_yticklabels(y_labels, fontsize=9)
    ax.set_xlabel('Simulation Time (ns)', fontsize=12, fontweight='bold')
    ax.set_title('Task Execution Gantt Chart (First 60 Tasks)', fontsize=16, fontweight='bold')
    ax.grid(True, linestyle=':', alpha=0.6, axis='x')
    
    # Clean up legend
    handles, labels = ax.get_legend_handles_labels()
    by_label = dict(zip(labels, handles))
    ax.legend(by_label.values(), by_label.keys(), loc='upper right')

    plt.tight_layout()
    plt.savefig(OUTPUT_IMAGE, dpi=300)
    print(f"Gantt chart saved to {OUTPUT_IMAGE}")

if __name__ == "__main__":
    main()