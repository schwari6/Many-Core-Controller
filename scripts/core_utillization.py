import matplotlib.pyplot as plt
import os

# -------------------------------------------------------------------------
# Dynamic Path Resolution
# -------------------------------------------------------------------------
# Find the directory where this script is located (SCRIPTS/)
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))

# Navigate relative to the script location to find REPORTS/
LOG_FILE_PATH = os.path.join(SCRIPT_DIR, '../REPORTS/sim_log.txt')
OUTPUT_IMAGE  = os.path.join(SCRIPT_DIR, '../REPORTS/core_utilization_graph.png')

def main():
    if not os.path.exists(LOG_FILE_PATH):
        print(f"Error: The file '{LOG_FILE_PATH}' was not found.")
        print("Please run the simulation first and save the log in the REPORTS directory.")
        return

    times = []
    active_cores = []

    print(f"Parsing log file: {LOG_FILE_PATH}...")

    # -------------------------------------------------------------------------
    # Parsing
    # -------------------------------------------------------------------------
    with open(LOG_FILE_PATH, 'r') as file:
        for line in file:
            if "CSV_LOG" in line:
                try:
                    csv_part = line[line.find("CSV_LOG"):]
                    parts = csv_part.strip().split(',')
                    
                    if len(parts) >= 3:
                        t = float(parts[1])
                        c = int(parts[2])
                        
                        times.append(t)
                        active_cores.append(c)
                except ValueError:
                    continue

    if not times:
        print("No CSV_LOG data found in the file.")
        return

    print(f"Successfully loaded {len(times)} data points. Generating graph...")

    # -------------------------------------------------------------------------
    # Plotting
    # -------------------------------------------------------------------------
    plt.figure(figsize=(12, 6))
    
    plt.step(times, active_cores, where='post', color='#1f77b4', linewidth=2, label='Active Cores')
    plt.fill_between(times, active_cores, step="post", alpha=0.3, color='#1f77b4')

    plt.axhline(y=64, color='red', linestyle='--', alpha=0.7, label='System Capacity (64 Cores)')

    plt.title('Hardware Controller: Core Utilization Over Time', fontsize=16, fontweight='bold')
    plt.xlabel('Simulation Time (ns / ps)', fontsize=14)
    plt.ylabel('Number of Active Cores', fontsize=14)
    plt.ylim(-2, 70)
    plt.grid(True, linestyle=':', alpha=0.8)
    plt.legend(loc='upper right', fontsize=12)
    
    plt.tight_layout()

    # Save to REPORTS directory
    plt.savefig(OUTPUT_IMAGE, dpi=300)
    print(f"Graph saved successfully as: {os.path.abspath(OUTPUT_IMAGE)}")

    # Show on screen
    plt.show()

if __name__ == '__main__':
    main()
