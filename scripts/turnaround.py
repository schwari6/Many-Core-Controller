import matplotlib.pyplot as plt
import statistics
import os

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
LOG_FILE_PATH = os.path.join(SCRIPT_DIR, '../reports/sim_log.txt')
OUTPUT_IMAGE = os.path.join(SCRIPT_DIR, '../reports/graph_5_turnaround.png')

def main():
    if not os.path.exists(LOG_FILE_PATH):
        print(f"Error: {LOG_FILE_PATH} not found.")
        return

    task_host_time = {}           
    task_end_time = {}            

    with open(LOG_FILE_PATH, 'r') as file:
        for line in file:
            if "LOG_HOST" in line:
                _, t, tid, _, _ = line.strip().split(',')
                task_host_time[int(tid)] = float(t)
            elif "LOG_FREE" in line:
                _, t, tid, _ = line.strip().split(',')
                tid = int(tid)
                if tid in task_host_time:
                    task_end_time[tid] = float(t)

    tids = []
    turnarounds = []
    
    for tid in sorted(task_host_time.keys()):
        if tid in task_end_time:
            tt = task_end_time[tid] - task_host_time[tid]
            tids.append(f"Task {tid}")
            turnarounds.append(tt)

    if not turnarounds:
        print("No completed tasks found for turnaround analysis.")
        return

    # Calculate Statistics
    avg_tt = statistics.mean(turnarounds)
    std_tt = statistics.stdev(turnarounds) if len(turnarounds) > 1 else 0

    # Limit to first 50 tasks for plotting readability
    plot_tids = tids[:50]
    plot_turnarounds = turnarounds[:50]

    plt.figure(figsize=(14, 6))
    bars = plt.bar(plot_tids, plot_turnarounds, color='#9467bd', edgecolor='black', alpha=0.8)
    
    for bar in bars:
        yval = bar.get_height()
        plt.text(bar.get_x() + bar.get_width()/2.0, yval + (max(plot_turnarounds)*0.01), 
                 f'{int(yval)}', ha='center', va='bottom', fontsize=8, rotation=45)

    plt.title('Absolute Task Turnaround Time (Sample of 50 Tasks)', fontsize=14, fontweight='bold')
    plt.xlabel('Task ID', fontsize=12)
    plt.ylabel('Turnaround Time (ns)', fontsize=12)
    plt.xticks(rotation=45, ha='right', fontsize=9)
    plt.grid(axis='y', linestyle='--', alpha=0.7)

    # Add Statistics Text Box
    stats_text = f"Total Tasks: {len(turnarounds)}\nAverage: {avg_tt:.1f} ns\nStd Dev: {std_tt:.1f} ns"
    props = dict(boxstyle='round', facecolor='white', alpha=0.9, edgecolor='gray')
    plt.gca().text(0.95, 0.95, stats_text, transform=plt.gca().transAxes, fontsize=12,
            verticalalignment='top', horizontalalignment='right', bbox=props, fontweight='bold', color='#333333')

    plt.tight_layout()
    plt.savefig(OUTPUT_IMAGE, dpi=300)
    print(f"Turnaround graph saved to {OUTPUT_IMAGE}")

if __name__ == "__main__":
    main()