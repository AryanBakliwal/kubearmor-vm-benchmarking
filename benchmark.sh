#!/bin/bash
set -e

# Cleanup function for unexpected exits
cleanup() {
    echo "Cleaning up..."
    kill $(jobs -p) 2>/dev/null || true
    docker compose -f manifests/voting-app.yaml down 2>/dev/null || true
    docker compose -f manifests/kubearmor-compose.yaml down -v 2>/dev/null || true
}
trap cleanup EXIT

if [ "$#" -ne 2 ]; then
    echo "Usage: $0 <kubearmor_version> <enforcer>"
    echo "Example: $0 v1.6.15 bpf"
    exit 1
fi

export KA_VERSION=$1
export ENFORCER=$2 # apparmor or bpf

export KA_HOSTNAME=$(hostname)

# Define all scenarios in the exact order they should execute
SCENARIOS=(
    "baseline_no_kubearmor"
    "baseline_kubearmor"
    "vis_process"
    "vis_process_file"
    "vis_process_network_file"
    "vis_network_policy_enforcer"
    "pol_process"
    "pol_process_file"
    "pol_process_network_file"
    "pol_network_policy_enforcer"
    "max_load"
)

echo "=========================================================="
echo "Starting Full Benchmark Suite: $KA_VERSION | $ENFORCER"
echo "=========================================================="

for SCENARIO in "${SCENARIOS[@]}"; do

    export SCENARIO
    echo "----------------------------------------------------------"
    echo "Running Scenario: $SCENARIO"
    echo "----------------------------------------------------------"

    RESULTS_DIR="results/${KA_VERSION}/${SCENARIO}/${ENFORCER}"
    mkdir -p "$RESULTS_DIR"

    # Configure KubeArmor based on Scenario
    export KA_DYNAMIC_ARGS=""
    export PROC_POL="false"
    export FILE_POL="false"
    export NET_POL="false"
    export NS_POL="false"

    case $SCENARIO in
        "baseline_no_kubearmor")
            echo "Skipping KubeArmor installation for baseline..."
            ;;
        "baseline_kubearmor")
            KA_DYNAMIC_ARGS="-visibility=none -hostVisibility=none -enableNetworkPolicyEnforcer=false"
            ;;
        "vis_process")
            KA_DYNAMIC_ARGS="-visibility=process -hostVisibility=process -enableNetworkPolicyEnforcer=false"
            ;;
        "vis_process_file")
            KA_DYNAMIC_ARGS="-visibility=process,file -hostVisibility=process,file -enableNetworkPolicyEnforcer=false"
            ;;
        "vis_process_network_file")
            KA_DYNAMIC_ARGS="-visibility=process,network,file -hostVisibility=process,network,file -enableNetworkPolicyEnforcer=false"
            ;;
        "vis_network_policy_enforcer")
            KA_DYNAMIC_ARGS="-visibility=none -hostVisibility=none -enableNetworkPolicyEnforcer=true"
            ;;
        "pol_process")
            KA_DYNAMIC_ARGS="-visibility=none -hostVisibility=none -enableNetworkPolicyEnforcer=false"
            PROC_POL="true"
            ;;
        "pol_process_file")
            KA_DYNAMIC_ARGS="-visibility=none -hostVisibility=none -enableNetworkPolicyEnforcer=false"
            PROC_POL="true"
            FILE_POL="true"
            ;;
        "pol_process_network_file")
            KA_DYNAMIC_ARGS="-visibility=none -hostVisibility=none -enableNetworkPolicyEnforcer=false"
            PROC_POL="true"
            FILE_POL="true"
            NET_POL="true"
            ;;
        "pol_network_policy_enforcer")
            KA_DYNAMIC_ARGS="-visibility=none -hostVisibility=none -enableNetworkPolicyEnforcer=true"
            NS_POL="true"
            ;;
        "max_load")
            KA_DYNAMIC_ARGS="-visibility=process,network,file -hostVisibility=process,network,file -enableNetworkPolicyEnforcer=true"
            PROC_POL="true"
            FILE_POL="true"
            NET_POL="true"
            NS_POL="true"
            ;;
        *)
            echo "Warning: Scenario $SCENARIO not explicitly mapped. Using defaults."
            ;;
    esac

    # Start KubeArmor
    if [ "$SCENARIO" != "baseline_no_kubearmor" ]; then
        echo "Starting KubeArmor container via Compose..."
        docker compose -f manifests/kubearmor-compose.yaml up -d
        
        echo "Waiting for KubeArmor to initialize (60s)..."
        sleep 60
    fi

    # Deploy Workload (Voting app)
    echo "Deploying Voting app workload..."
    docker compose -f manifests/voting-app.yaml up -d
    echo "Waiting for Voting app to stabilize (30s)..."
    sleep 30

    # Apply policy
    if [ "$PROC_POL" != "false" ]; then
        echo "Applying process KSP"
        karmor vm policy add manifests/proc_pol.yaml
        echo "Applying process HSP"
        karmor vm policy add manifests/host_proc_pol.yaml
    fi

    if [ "$FILE_POL" != "false" ]; then
        echo "Applying file KSP"
        karmor vm policy add manifests/file_pol.yaml
        echo "Applying file HSP"
        karmor vm policy add manifests/host_file_pol.yaml
    fi

    if [ "$NET_POL" != "false" ]; then
        echo "Applying network KSP"
        karmor vm policy add manifests/net_pol.yaml
        echo "Applying network HSP"
        karmor vm policy add manifests/host_net_pol.yaml
    fi

    if [ "$NS_POL" != "false" ]; then
        echo "Applying NSP"
        karmor vm policy add manifests/ns_pol.yaml
    fi

    echo "Starting metrics collection..."

    # Capture Total RAM in MB
    free -m | awk '/Mem:/ { print $2 }' > "${RESULTS_DIR}/total_mem.txt"

    # Host metrics
    vmstat 5 > "${RESULTS_DIR}/host_vmstat.txt" &
    VMSTAT_PID=$!

    # Only if KubeArmor is running
    if [ "$SCENARIO" != "baseline_no_kubearmor" ]; then
        ( while true; do
            docker stats --no-stream --format "{{.CPUPerc}},{{.MemUsage}},{{.MemPerc}},{{.NetIO}},{{.BlockIO}}" kubearmor >> "${RESULTS_DIR}/ka_stats.csv"
            sleep 1
        done ) &
        DOCKER_STATS_PID=$!
    fi

    # Generate Traffic
    echo "Generating traffic with Locust..."
    locust -f tools/locustfile.py --headless -u 100 -r 10 --run-time 2m \
        --csv="${RESULTS_DIR}/locust" --host=http://localhost:8080

    # Teardown
    echo "Stopping metrics collection..."
    kill $VMSTAT_PID || true
    if [ "$SCENARIO" != "baseline_no_kubearmor" ]; then
        kill $DOCKER_STATS_PID
    fi

    # Delete policy
    if [ "$PROC_POL" != "false" ]; then
        echo "Deleting process KSP"
        karmor vm policy delete manifests/proc_pol.yaml
        echo "Deleting process HSP"
        karmor vm policy delete manifests/host_proc_pol.yaml
    fi

    if [ "$FILE_POL" != "false" ]; then
        echo "Deleting file KSP"
        karmor vm policy delete manifests/file_pol.yaml
        echo "Deleting file HSP"
        karmor vm policy delete manifests/host_file_pol.yaml
    fi

    if [ "$NET_POL" != "false" ]; then
        echo "Deleting network KSP"
        karmor vm policy delete manifests/net_pol.yaml
        echo "Deleting network HSP"
        karmor vm policy delete manifests/host_net_pol.yaml
    fi

    if [ "$NS_POL" != "false" ]; then
        echo "Deleting NSP"
        karmor vm policy delete manifests/ns_pol.yaml
    fi

    echo "Tearing down workload and KubeArmor..."
    docker compose -f manifests/voting-app.yaml down

    if [ "$SCENARIO" != "baseline_no_kubearmor" ]; then
        docker compose -f manifests/kubearmor-compose.yaml down -v
    fi

    echo "Benchmark for $SCENARIO complete. Results saved in $RESULTS_DIR."
    sleep 30

done

echo "=========================================================="
echo "All scenarios complete! Generating final report..."
echo "=========================================================="

python tools/gen_report.py "$KA_VERSION" "$ENFORCER"

echo "Done! Run successfully finished."