#!/bin/bash
# Ray head node startup script for spark-f5ea (192.168.100.10)
# To install as systemd service: see ray/systemd/ray-head.service

set -e

export MN_IF_NAME=enp1s0f0np0
export VLLM_IMAGE=nvcr.io/nvidia/vllm:26.02-py3

# Assign static IP to QSFP interface if not already set
if ! ip -4 addr show "$MN_IF_NAME" | awk '/inet / && !/169.254/' | grep -q inet; then
    echo "Assigning IP to $MN_IF_NAME..."
    sudo ip addr add 192.168.100.10/24 dev "$MN_IF_NAME"
fi

export VLLM_HOST_IP=$(ip -4 addr show "$MN_IF_NAME" | awk '/inet / && !/169.254/ {print $2}' | cut -d/ -f1)
echo "Starting Ray head node on $MN_IF_NAME with IP $VLLM_HOST_IP"

bash ~/run_cluster.sh "$VLLM_IMAGE" "$VLLM_HOST_IP" --head ~/.cache/huggingface -e VLLM_HOST_IP="$VLLM_HOST_IP" -e UCX_NET_DEVICES="$MN_IF_NAME" -e NCCL_SOCKET_IFNAME="$MN_IF_NAME" -e OMPI_MCA_btl_tcp_if_include="$MN_IF_NAME" -e GLOO_SOCKET_IFNAME="$MN_IF_NAME" -e TP_SOCKET_IFNAME="$MN_IF_NAME" -e RAY_memory_monitor_refresh_ms=0 -e MASTER_ADDR="$VLLM_HOST_IP"
