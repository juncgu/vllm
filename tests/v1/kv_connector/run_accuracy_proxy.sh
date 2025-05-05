#!/bin/bash

set -xe

# Model to run.
MODEL_NAME=meta-llama/Llama-3.2-3B-Instruct

# Trap the SIGINT signal (triggered by Ctrl+C)
trap 'kill $(jobs -pr)' SIGINT SIGTERM EXIT

# Cleanup function
cleanup() {
    echo "Caught Ctrl+C, cleaning up..."
    # Cleanup commands
    pgrep python | xargs kill -9
    pkill -f python
    echo "Cleanup complete. Exiting."
    exit 0
}
PREFILL_HOST="10.138.0.14"
DECODE_HOST="10.128.0.28"
PROXY_HOST="localhost"

# Waits for vLLM to start.
wait_for_server() {
  local host=$1
  local port=$2
  timeout 1200 bash -c "
    until curl -s ${host}:${port}/v1/completions > /dev/null; do
      sleep 1
    done" && return 0 || return 1
}

# Prefill instance.
# VLLM_LOGGING_LEVEL=DEBUG \
# VLLM_USE_V1=1 \
# VLLM_NIXL_CPU=1 \
# TPU_PROCESS_BOUNDS=1,1,1 \
# TPU_VISIBLE_CHIPS=0 \
# PJRT_DEVICE=TPU \
# VLLM_WORKER_MULTIPROC_METHOD=spawn \
# VLLM_ENABLE_V1_MULTIPROCESSING=0 \
# VLLM_DEBUG_INITIAL_NIXL_PD_XFER=1 \
# NIXL_ROLE="SENDER" vllm serve $MODEL_NAME \
#     --port 8100 \
#     --max-model-len 8192 \
#     --enforce-eager \
#     --disable-log-requests \
#     --kv-transfer-config '{"kv_connector":"NixlConnector","kv_role":"kv_both"}' &

# # Decode instance.
# VLLM_LOGGING_LEVEL=DEBUG \
# VLLM_USE_V1=1 \
# VLLM_NIXL_CPU=1 \
# TPU_PROCESS_BOUNDS=1,1,1 \
# TPU_VISIBLE_CHIPS=1 \
# PJRT_DEVICE=TPU \
# VLLM_WORKER_MULTIPROC_METHOD=spawn \
# VLLM_ENABLE_V1_MULTIPROCESSING=0 \
# VLLM_DEBUG_INITIAL_NIXL_PD_XFER=1 \
# NIXL_ROLE="RECVER" vllm serve $MODEL_NAME \
#     --port 8200 \
#     --max-model-len 8192 \
#     --enforce-eager \
#     --disable-log-requests \
#     --kv-transfer-config '{"kv_connector":"NixlConnector","kv_role":"kv_both"}' &

# wait until prefill and decode instances are ready
wait_for_server ${PREFILL_HOST} 8100
wait_for_server ${DECODE_HOST} 8200

# Proxy server.
# python toy_proxy_server.py --port 8192 &
python toy_proxy_server.py --prefiller-host ${PREFILL_HOST} --prefiller-port 8100 --decoder-host ${DECODE_HOST} --decoder-port 8200 --host=${PROXY_HOST} --port 8192 &

wait_for_server ${PROXY_HOST} 8192
echo "now servers are ready"
sleep 1000

# Run lm eval.
# python3 -m pytest -s -x test_accuracy.py

# curl -X POST http://localhost:8192/v1/completions \
#     -H "Content-Type: application/json" \
#     -d '{"model": "meta-llama/Llama-3.2-3B-Instruct", "prompt": "Who is the president of US, ", "max_tokens": 30, "temperature": 0.7}'
# sleep 1
