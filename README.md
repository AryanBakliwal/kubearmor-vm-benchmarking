# KubeArmor VM Performance Benchmarking

This project provides an script for benchmarking **KubeArmor** in VM mode (running as a Docker container). It measures the performance impact of various visibility and enforcement scenarios using the **Docker Voting App** as the target workload and **Locust** for traffic generation.

## 🚀 Quick Start

### 1. Environment Setup
The reporting and load-generation tools require Python 3. We use a virtual environment to keep the host system clean.

```bash
# Create the virtual environment
python3 -m venv tools/venv

# Activate the environment
source tools/venv/bin/activate

# Install dependencies
pip install -r requirements.txt
```

> **Note:** Ensure you have `docker` and `docker-compose` installed and that your user has permissions to run them. [`karmor`](https://github.com/kubearmor/kubearmor-client/) should also be installed.

### 2. Run the Benchmark
The `benchmark.sh` script automates the entire process: deploying KubeArmor, starting the workload, applying policies, and collecting metrics.

**Usage:**
```bash
./benchmark.sh <kubearmor_version> <enforcer>
```

**Examples:**
```bash
# Benchmark using the eBPF enforcer
./benchmark.sh v1.6.18 bpf

# Benchmark using the AppArmor enforcer
./benchmark.sh v1.6.18 apparmor
```

---

## 📊 How it Works

### Scenarios Tested
The suite executes the following scenarios in order:
1. **Baseline (No KubeArmor):** Raw application performance.
2. **Visibility Modes:** Measures overhead of Process, File, and Network visibility.
3. **Policy Enforcement:** Measures overhead when active security policies are applied.
4. **Max Load:** All visibility and enforcement features enabled simultaneously.

### Metrics Collected
* **App Throughput:** Requests per second (req/s).
* **App Latency:** Average response time in milliseconds.
* **KubeArmor Overhead:** CPU and Memory usage of the KubeArmor container.
* **Host Stats:** Overall system CPU util, RAM usage (Used/Total), and Disk I/O.

---

## 📂 Project Structure
* `benchmark.sh`: The main execution script.
* `manifests/`: Contains Docker Compose files and KubeArmor policies.
* `tools/`:
    * `locustfile.py`: Defines the traffic pattern for the Voting App.
    * `gen_report.py`: Aggregates raw CSV/TXT data into a final Markdown report.
    * `venv/`: Your Python virtual environment (ignored by git).

## 📝 Result Output
Once the script finishes, it generates a markdown report in the root directory:
`benchmark_report_<version>_<enforcer>.md`