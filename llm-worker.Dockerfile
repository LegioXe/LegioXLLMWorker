# ARCHITECTURAL NOTE: Base Image Selection
# We start from an official RunPod PyTorch image. This is a critical choice because it provides a pre-configured, optimized environment
# with the correct NVIDIA drivers, CUDA toolkit, and PyTorch libraries. This saves significant build time and eliminates potential
# compatibility issues between the OS, the drivers, and the model serving framework.
# llm-worker.Dockerfile

# ==============================================================================
# STAGE 1: The "Builder" Stage
# ==============================================================================
FROM runpod/pytorch:2.2.0-py3.10-cuda12.1.1-devel-ubuntu22.04 as builder

LABEL maintainer="AIOS Project"
ENV DEBIAN_FRONTEND=noninteractive
ARG HF_TOKEN

# Set model names for Ollama create command
ENV PHI3_MINI_MODEL=phi3:3.8b-mini-instruct-4k-q5_k_m
ENV PHI3_SMALL_MODEL=phi3:7b-small-instruct-4k-q5_k_m
ENV PHI3_MEDIUM_MODEL=phi3:14b-medium-instruct-4k-q5_k_m

# Install dependencies needed for the build stage
RUN apt-get update && apt-get install -y --no-install-recommends curl ca-certificates && \
    apt-get clean && rm -rf /var/lib/apt/lists/* && \
    curl -fsSL https://ollama.com/install.sh | sh

WORKDIR /app
COPY modelfiles/ /app/modelfiles/

# Download, create models, and then clean up
# CORRECTED: Added --progress-bar (-#) to curl for better real-time feedback
RUN /bin/bash -c "set -e && \
    mkdir -p /tmp/models && \
    CURL_OPTS='--fail -L --retry 3 --retry-delay 5 --connect-timeout 20 -# -H \"Authorization: Bearer $HF_TOKEN\"' && \
    \
    echo '--- Downloading Models ---' && \
    curl \$CURL_OPTS 'https://huggingface.co/bartowski/Phi-3-mini-4k-instruct-GGUF/resolve/main/Phi-3-mini-4k-instruct-Q5_K_M.gguf' -o /tmp/models/phi3-mini.gguf && \
    curl \$CURL_OPTS 'https://huggingface.co/TheBloke/Phi-3-small-8k-instruct-GGUF/resolve/main/phi-3-small-8k-instruct.q5_k_m.gguf' -o /tmp/models/phi3-small.gguf && \
    curl \$CURL_OPTS 'https://huggingface.co/TheBloke/Phi-3-medium-4k-instruct-GGUF/resolve/main/phi-3-medium-4k-instruct.q5_k_m.gguf' -o /tmp/models/phi3-medium.gguf && \
    \
    echo '--- Creating Ollama models ---' && \
    ollama serve & \
    echo 'Waiting for Ollama server to start...' && \
    while ! curl -s -f http://127.0.0.1:11434/ > /dev/null; do echo -n '.' && sleep 1; done && \
    echo 'Ollama server is ready.' && \
    \
    ollama create ${PHI3_MINI_MODEL} -f /app/modelfiles/Phi3Mini.Modelfile && \
    ollama create ${PHI3_SMALL_MODEL} -f /app/modelfiles/Phi3Small.Modelfile && \
    ollama create ${PHI3_MEDIUM_MODEL} -f /app/modelfiles/Phi3Medium.Modelfile && \
    \
    echo '--- Cleanup ---' && \
    pkill ollama && \
    rm -rf /tmp/models"


# ==============================================================================
# STAGE 2: The Final, Lean Image
# ==============================================================================
FROM runpod/pytorch:2.2.0-py3.10-cuda12.1.1-devel-ubuntu22.04

LABEL maintainer="AIOS Project"
ENV DEBIAN_FRONTEND=noninteractive

# Install Ollama again in the final image
RUN apt-get update && apt-get install -y --no-install-recommends curl ca-certificates && \
    apt-get clean && rm -rf /var/lib/apt/lists/* && \
    curl -fsSL https://ollama.com/install.sh | sh

# Copy the pre-built Ollama models from the builder stage.
COPY --from=builder /root/.ollama/models /root/.ollama/models

# Copy the final application code and dependencies
WORKDIR /app
COPY llm-worker-requirements.txt .
RUN pip install --no-cache-dir -r llm-worker-requirements.txt
COPY worker_api.py .
COPY start.sh .
RUN chmod +x ./start.sh

EXPOSE 8000
CMD ["./start.sh"]

