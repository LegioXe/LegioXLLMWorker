# llm-worker.Dockerfile

# ARCHITECTURAL NOTE: Base Image Selection
# We start from an official RunPod PyTorch image. This is a critical choice because it provides a pre-configured, optimized environment
# with the correct NVIDIA drivers, CUDA toolkit, and PyTorch libraries. This saves significant build time and eliminates potential
# compatibility issues between the OS, the drivers, and the model serving framework.
#
FROM runpod/pytorch:2.2.0-py3.10-cuda12.1.1-devel-ubuntu22.04

LABEL maintainer="AIOS Project"
LABEL description="A high-performance LLM worker for AIOS, serving multiple models via Ollama. Models are pre-pulled to minimize cold starts."

ENV DEBIAN_FRONTEND=noninteractive
ENV PHI3_MINI_MODEL=phi3:3.8b-mini-instruct-4k-q5_K_M
ENV PHI3_SMALL_MODEL=phi3:7b-small-instruct-4k-q5_K_M
ENV PHI3_MEDIUM_MODEL=phi3:14b-medium-instruct-4k-q5_K_M
ENV DEEPSEEK_CODER_MODEL=deepseek-coder-v2:16b-lite-instruct-q5_K_M

# STAGE 1: System & Ollama Installation
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Use the official Ollama installation script for a reliable setup.
RUN curl -fsSL https://ollama.com/install.sh | sh

# Copy the Modelfile definitions into the container.
COPY modelfiles/ /app/modelfiles

#
# STAGE 2: Model Creation (The "Baking" Process)
#
# --- FIX: Start the ollama server in the background OF THE SAME RUN COMMAND ---
# ARCHITECTURAL NOTE: Self-Contained Build Step
# This is the crucial fix. The 'ollama create' command needs a running server. By launching
# 'ollama serve &' at the beginning of this single RUN command, we provide a temporary,
# background server that exists only for this layer. The 'create' commands connect to it,
# download and package the models, and then 'pkill ollama' cleanly shuts down the temporary
# server before the layer is finalized. This makes the build process self-contained and robust.
#
RUN /bin/bash -c 'ollama serve & sleep 5 && \
    echo "--- Creating Phi-3 Mini (3.8B) ---" && \
    ollama create ${PHI3_MINI_MODEL} -f /app/modelfiles/Phi3Mini.Modelfile && \
    echo "--- Creating Phi-3 Small (7B) ---" && \
    ollama create ${PHI3_SMALL_MODEL} -f /app/modelfiles/Phi3Small.Modelfile && \
    echo "--- Creating Phi-3 Medium (14B) ---" && \
    ollama create ${PHI3_MEDIUM_MODEL} -f /app/modelfiles/Phi3Medium.Modelfile && \
    echo "--- Creating DeepSeek Coder V2 Lite (16B) ---" && \
    ollama create ${DEEPSEEK_CODER_MODEL} -f /app/modelfiles/DeepseekCoder.Modelfile && \
    pkill ollama'

# STAGE 3: Application Setup
WORKDIR /app
COPY llm-worker-requirements.txt .
RUN pip install --no-cache-dir -r llm-worker-requirements.txt
COPY worker_api.py .

# STAGE 4: Runtime Configuration
EXPOSE 8000
COPY start.sh .
RUN chmod +x ./start.sh
CMD ["./start.sh"]
