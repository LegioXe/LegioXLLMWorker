# ARCHITECTURAL NOTE: Base Image Selection
# We start from an official RunPod PyTorch image. This is a critical choice because it provides a pre-configured, optimized environment
# with the correct NVIDIA drivers, CUDA toolkit, and PyTorch libraries. This saves significant build time and eliminates potential
# compatibility issues between the OS, the drivers, and the model serving framework.
# llm-worker.Dockerfile

# STAGE 1: Base Image and System Dependencies
FROM runpod/pytorch:2.2.0-py3.10-cuda12.1.1-devel-ubuntu22.04
LABEL maintainer="AIOS Project"
LABEL description="A high-performance LLM worker for AIOS, serving multiple models via Ollama. Models are pre-pulled to minimize cold starts."
ENV DEBIAN_FRONTEND=noninteractive

# Use all lowercase for Ollama model tags
ENV PHI3_MINI_MODEL=phi3:3.8b-mini-instruct-4k-q5_k_m
ENV PHI3_SMALL_MODEL=phi3:7b-small-instruct-4k-q5_k_m
ENV PHI3_MEDIUM_MODEL=phi3:14b-medium-instruct-4k-q5_k_m
ENV DEEPSEEK_CODER_MODEL=deepseek-coder-v2:16b-lite-instruct-q5_k_m

RUN apt-get update && apt-get install -y --no-install-recommends curl ca-certificates && \
    apt-get clean && rm -rf /var/lib/apt/lists/* && \
    curl -fsSL https://ollama.com/install.sh | sh

WORKDIR /app
COPY modelfiles/ /app/modelfiles/

# STAGE 2: Pre-download and Create Models
# CORRECTED: Use double quotes for the bash command to allow variable expansion
RUN /bin/bash -c "set -e && \
    mkdir -p /tmp/models && \
    echo '--- Downloading Models ---' && \
    curl --fail -L 'https://huggingface.co/bartowski/Phi-3-mini-4k-instruct-GGUF/resolve/main/Phi-3-mini-4k-instruct-Q5_K_M.gguf' -o /tmp/models/phi3-mini.gguf && \
    curl --fail -L 'https://huggingface.co/TheBloke/Phi-3-small-8k-instruct-GGUF/resolve/main/phi-3-small-8k-instruct.q5_k_m.gguf' -o /tmp/models/phi3-small.gguf && \
    curl --fail -L 'https://huggingface.co/TheBloke/Phi-3-medium-4k-instruct-GGUF/resolve/main/phi-3-medium-4k-instruct.q5_k_m.gguf' -o /tmp/models/phi3-medium.gguf && \
    curl --fail -L 'https://huggingface.co/TheBloke/DeepSeek-Coder-V2-Lite-Instruct-GGUF/resolve/main/deepseek-coder-v2-lite-instruct.q5_k_m.gguf' -o /tmp/models/deepseek-coder.gguf && \
    \
    echo '--- Creating Ollama models ---' && \
    ollama serve & \
    sleep 5 && \
    ollama create ${PHI3_MINI_MODEL} -f /app/modelfiles/Phi3Mini.Modelfile && \
    ollama create ${PHI3_SMALL_MODEL} -f /app/modelfiles/Phi3Small.Modelfile && \
    ollama create ${PHI3_MEDIUM_MODEL} -f /app/modelfiles/Phi3Medium.Modelfile && \
    ollama create ${DEEPSEEK_CODER_MODEL} -f /app/modelfiles/DeepseekCoder.Modelfile && \
    \
    echo '--- Cleanup ---' && \
    pkill ollama && \
    rm -rf /tmp/models"

# STAGE 3: Final Application Setup
COPY llm-worker-requirements.txt .
RUN pip install --no-cache-dir -r llm-worker-requirements.txt
COPY worker_api.py .
COPY start.sh .
RUN chmod +x ./start.sh

EXPOSE 8000
CMD ["./start.sh"]

