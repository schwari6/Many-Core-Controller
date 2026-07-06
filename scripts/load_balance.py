import matplotlib.pyplot as plt
import os

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
LOG_FILE_PATH = os.path.join(SCRIPT_DIR, '../reports/sim_log.txt')
OUTPUT_IMAGE = os.path.join(SCRIPT_DIR, '../reports/graph_1_load_balance.png')

def main():
    if not os.path.exists(LOG_FILE_PATH):
        print(f"Error: {LOG_FILE_PATH} not found.")
        return

    core_time = {i: 0.0 for i in range(64)}
    core_start = {}
    max_t = 0.0

    with open(LOG_FILE_PATH, 'r') as file:
        for line in file:
            if "LOG_SYS" in line:
                _, t, _, _ = line.strip().split(',')
                max_t = float(t)
            elif "LOG_ALLOC" in line:
                _, t, _, cid = line.strip().split(',')
                core_start[int(cid)] = float(t)
            elif "LOG_FREE" in line:
                _, t, _, cid = line.strip().split(',')
                cid = int(cid)
                if cid in core_start:
                    core_time[cid] += (float(t) - core_start[cid])
                    del core_start[cid]

    # Handle remaining running cores at end of simulation
    for cid, start_t in core_start.items():
        core_time[cid] += (max_t - start_t)

    cores = list(core_time.keys())
    utilization = [(time / max_t) * 100 if max_t > 0 else 0 for time in core_time.values()]
    
    plt.figure(figsize=(12, 5))
    plt.bar(cores, utilization, color='#2ca02c', edgecolor='black', alpha=0.8)
    plt.title('Core Load Balancing (Wear Leveling Check)', fontsize=14, fontweight='bold')
    plt.xlabel('Core ID (0 to 63)', fontsize=12)
    plt.ylabel('Active Time (%)', fontsize=12)
    plt.xlim(-1, 64)
    plt.grid(axis='y', linestyle='--', alpha=0.7)
    
    plt.tight_layout()
    plt.savefig(OUTPUT_IMAGE, dpi=300)
    print(f"Saved: {os.path.abspath(OUTPUT_IMAGE)}")

if __name__ == '__main__':
    main()
