# ARCHITECTURAL NOTE: Base Image Selection
# We start from an official RunPod PyTorch image. This is a critical choice because it provides a pre-configured, optimized environment
# with the correct NVIDIA drivers, CUDA toolkit, and PyTorch libraries. This saves significant build time and eliminates potential
# compatibility issues between the OS, the drivers, and the model serving framework.
FROM runpod/pytorch:2.2.0-py3.10-cuda12.1.1-devel-ubuntu22.04

LABEL maintainer="AIOS Project"
LABEL description="A high-performance LLM worker for AIOS, serving multiple models via Ollama. Models are pre-pulled to minimize cold starts."

ENV DEBIAN_FRONTEND=noninteractive

# CORRECTED: Ollama tags must be entirely lowercase.
ENV PHI3_MINI_MODEL=phi3:3.8b-mini-instruct-4k-q5_k_m
ENV PHI3_SMALL_MODEL=phi3:7b-small-instruct-4k-q5_k_m
ENV PHI3_MEDIUM_MODEL=phi3:14b-medium-instruct-4k-q5_k_m
ENV DEEPSEEK_CODER_MODEL=deepseek-coder-v2:16b-lite-instruct-q5_k_m

# STAGE 1: System & Dependency Installation
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://ollama.com/install.sh | sh

# STAGE 2: Pre-download Model Files
RUN mkdir -p /tmp/models
ARG HF_TOKEN

# --- Using curl with CORRECT, case-sensitive filenames ---

# CORRECTED: Filename for Phi-3-mini starts with a capital 'P' and 'M'.
RUN echo "Downloading Phi-3 Mini..." && \
    curl --fail -L -H "Authorization: Bearer ${HF_TOKEN}" \
    "https://huggingface.co/bartowski/Phi-3-mini-4k-instruct-GGUF/resolve/main/Phi-3-mini-4k-instruct-Q5_K_M.gguf" \
    --output /tmp/models/Phi-3-mini-4k-instruct-Q5_K_M.gguf

# TheBloke's filenames are all lowercase.
RUN echo "Downloading Phi-3 Small..." && \
    curl --fail -L -H "Authorization: Bearer ${HF_TOKEN}" \
    "https://huggingface.co/TheBloke/Phi-3-small-8k-instruct-GGUF/resolve/main/phi-3-small-8k-instruct.Q5_K_M.gguf" \
    --output /tmp/models/phi-3-small-8k-instruct.Q5_K_M.gguf

RUN echo "Downloading Phi-3 Medium..." && \
    curl --fail -L -H "Authorization: Bearer ${HF_TOKEN}" \
    "https://huggingface.co/TheBloke/Phi-3-medium-4k-instruct-GGUF/resolve/main/phi-3-medium-4k-instruct.Q5_K_M.gguf" \
    --output /tmp/models/phi-3-medium-4k-instruct.Q5_K_M.gguf

RUN echo "Downloading DeepSeek Coder..." && \
    curl --fail -L -H "Authorization: Bearer ${HF_TOKEN}" \
    "https://huggingface.co/TheBloke/DeepSeek-Coder-V2-Lite-Instruct-GGUF/resolve/main/deepseek-coder-v2-lite-instruct.Q5_K_M.gguf" \
    --output /tmp/models/deepseek-coder-v2-lite-instruct.Q5_K_M.gguf

# CORRECTED: Rename the files using their proper case-sensitive source names.
RUN mv /tmp/models/Phi-3-mini-4k-instruct-Q5_K_M.gguf /tmp/models/phi3-mini.gguf
RUN mv /tmp/models/phi-3-small-8k-instruct.Q5_K_M.gguf /tmp/models/phi3-small.gguf
RUN mv /tmp/models/phi-3-medium-4k-instruct.Q5_K_M.gguf /tmp/models/phi3-medium.gguf
RUN mv /tmp/models/deepseek-coder-v2-lite-instruct.Q5_K_M.gguf /tmp/models/deepseek-coder.gguf

# STAGE 3: Model Creation from Local Files
COPY modelfiles/ /app/modelfiles

# The 'ollama serve' process must be running in the background for the 'create' command to work.
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
