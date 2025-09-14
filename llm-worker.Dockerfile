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

RUN curl -fsSL https://ollama.com/install.sh | sh

#
# STAGE 2: Pre-download Model Files
#
# --- THE DEFINITIVE FIX ---
# ARCHITECTURAL NOTE: Manual Download for CI/CD Robustness
# The core issue is the unreliability of Ollama's internal downloader in a CPU-only CI environment.
# To solve this permanently, we separate the download and creation steps. We use the robust and
# simple 'curl' command to manually download the model's GGUF file from a stable source (Hugging Face).
# This makes the download process explicit and removes the dependency on Ollama's client networking.
#
RUN mkdir -p /tmp/models
RUN curl -L "https://huggingface.co/microsoft/Phi-3-mini-4k-instruct-gguf/resolve/main/Phi-3-mini-4k-instruct-q5_K_M.gguf" -o /tmp/models/phi3-mini.gguf
RUN curl -L "https://huggingface.co/microsoft/Phi-3-small-8k-instruct-gguf/resolve/main/Phi-3-small-8k-instruct-Q5_K_M.gguf" -o /tmp/models/phi3-small.gguf
RUN curl -L "https://huggingface.co/microsoft/Phi-3-medium-4k-instruct-gguf/resolve/main/Phi-3-medium-4k-instruct-q5_K_M.gguf" -o /tmp/models/phi3-medium.gguf
RUN curl -L "https://huggingface.co/deepseek-ai/DeepSeek-Coder-V2-Lite-Instruct-GGUF/resolve/main/deepseek-coder-v2-lite-instruct.Q5_K_M.gguf" -o /tmp/models/deepseek-coder.gguf

# STAGE 3: Model Creation from Local Files
COPY modelfiles/ /app/modelfiles

# The 'ollama serve' is still needed for the 'create' command to function.
RUN /bin/bash -c 'ollama serve & sleep 5 && \
    echo "--- Creating Phi-3 Mini from local file ---" && \
    ollama create ${PHI3_MINI_MODEL} -f /app/modelfiles/Phi3Mini.Modelfile && \
    echo "--- Creating Phi-3 Small from local file ---" && \
    ollama create ${PHI3_SMALL_MODEL} -f /app/modelfiles/Phi3Small.Modelfile && \
    echo "--- Creating Phi-3 Medium from local file ---" && \
    ollama create ${PHI3_MEDIUM_MODEL} -f /app/modelfiles/Phi3Medium.Modelfile && \
    echo "--- Creating DeepSeek Coder from local file ---" && \
    ollama create ${DEEPSEEK_CODER_MODEL} -f /app/modelfiles/DeepseekCoder.Modelfile && \
    pkill ollama'

# STAGE 4: Cleanup and Application Setup
# Clean up the downloaded raw model files as they are now packaged by Ollama.
RUN rm -rf /tmp/models

WORKDIR /app
COPY llm-worker-requirements.txt .
RUN pip install --no-cache-dir -r llm-worker-requirements.txt
COPY worker_api.py .

# STAGE 5: Runtime Configuration
EXPOSE 8000
COPY start.sh .
RUN chmod +x ./start.sh
CMD ["./start.sh"]

