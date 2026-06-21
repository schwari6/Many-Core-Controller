import matplotlib.pyplot as plt
import collections
import os

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
LOG_FILE_PATH = os.path.join(SCRIPT_DIR, '../REPORTS/sim_log.txt')
OUTPUT_IMAGE = os.path.join(SCRIPT_DIR, '../REPORTS/graph_5_turnaround.png')

def main():
    if not os.path.exists(LOG_FILE_PATH):
        print(f"Error: {LOG_FILE_PATH} not found.")
        return

    task_host_time = {}           # When was the task injected?
    task_end_time = {}            # When did the LAST instance finish?

    with open(LOG_FILE_PATH, 'r') as file:
        for line in file:
            if "LOG_HOST" in line:
                _, t, tid, _, _ = line.strip().split(',')
                task_host_time[int(tid)] = float(t)
            elif "LOG_FREE" in line:
                _, t, tid, _ = line.strip().split(',')
                tid = int(tid)
                # Keep updating with the latest termination time
                # The last 'FREE' will overwrite previous ones, giving us the absolute end time.
                if tid in task_host_time:
                    task_end_time[tid] = float(t)

    # Calculate Turnaround Time
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

    plt.figure(figsize=(12, 6))
    
    # Plotting
    bars = plt.bar(tids, turnarounds, color='#9467bd', edgecolor='black', alpha=0.8)
    
    # Add actual values on top of the bars
    for bar in bars:
        yval = bar.get_height()
        plt.text(bar.get_x() + bar.get_width()/2.0, yval + (max(turnarounds)*0.01), 
                 f'{int(yval)} ns', ha='center', va='bottom', fontsize=10, fontweight='bold')

    plt.title('Absolute Task Turnaround Time (From Ingress to Full Completion)', fontsize=14, fontweight='bold')
    plt.xlabel('Task ID', fontsize=12)
    plt.ylabel('Turnaround Time (ns)', fontsize=12)
    plt.grid(axis='y', linestyle='--', alpha=0.7)
    
    # Rotate x labels if there are too many tasks
    if len(tids) > 10:
        plt.xticks(rotation=45, ha='right')
        
    plt.tight_layout()
    plt.savefig(OUTPUT_IMAGE, dpi=300)
    print(f"Saved: {os.path.abspath(OUTPUT_IMAGE)}")

if __name__ == '__main__':
    main()
