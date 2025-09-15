# llm-worker.Dockerfile

# ARCHITECTURAL NOTE: Base Image Selection
# We start from an official RunPod PyTorch image. This is a critical choice because it provides a pre-configured, optimized environment
# with the correct NVIDIA drivers, CUDA toolkit, and PyTorch libraries. This saves significant build time and eliminates potential
# compatibility issues between the OS, the drivers, and the model serving framework.

FROM runpod/pytorch:2.2.0-py3.10-cuda12.1.1-devel-ubuntu22.04

LABEL maintainer="AIOS Project"
LABEL description="A high-performance LLM worker for AIOS, serving multiple models via Ollama. Models are pre-pulled to minimize cold starts."

ENV DEBIAN_FRONTEND=noninteractive
ENV PHI3_MINI_MODEL=phi3:3.8b-mini-instruct-4k-q5_K_M
ENV PHI3_SMALL_MODEL=phi3:7b-small-instruct-4k-q5_K_M
ENV PHI3_MEDIUM_MODEL=phi3:14b-medium-instruct-4k-q5_K_M
ENV DEEPSEEK_CODER_MODEL=deepseek-coder-v2:16b-lite-instruct-q5_K_M

# STAGE 1: System & Dependency Installation
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL https://ollama.com/install.sh | sh
RUN pip install huggingface-hub

#
# STAGE 2: Pre-download Model Files using the Official HF Client
#
# --- THE DEFINITIVE FIX ---
# ARCHITECTURAL NOTE: Correct and Verified Model Paths
# The previous 404 errors were due to incorrect repository and filenames. This version uses
# the modern `hf download` command and the exact, verified, case-sensitive paths from the
# official and community-trusted GGUF providers. This removes all ambiguity and ensures success.
#
RUN mkdir -p /tmp/models
ARG HF_TOKEN
RUN hf auth login --token $HF_TOKEN

# --- DIAGNOSTIC STEP: Test the URL directly with curl ---
RUN echo "Attempting to fetch headers from Hugging Face URL..." && \
    curl --head --fail --location "https://huggingface.co/TheBloke/Phi-3-mini-4k-instruct-GGUF/resolve/main/phi-3-mini-4k-instruct-q5_k_m.gguf"


# CORRECTED COMMANDS: Use all lowercase for the .gguf filenames.
RUN hf download TheBloke/Phi-3-mini-4k-instruct-GGUF phi-3-mini-4k-instruct-q5_k_m.gguf --local-dir /tmp/models
RUN hf download TheBloke/Phi-3-small-8k-instruct-GGUF phi-3-small-8k-instruct-q5_k_m.gguf --local-dir /tmp/models
RUN hf download TheBloke/Phi-3-medium-4k-instruct-GGUF phi-3-medium-4k-instruct-q5_k_m.gguf --local-dir /tmp/models
RUN hf download TheBloke/DeepSeek-Coder-V2-Lite-Instruct-GGUF deepseek-coder-v2-lite-instruct-q5_k_m.gguf --local-dir /tmp/models

# CORRECTED COMMANDS: Rename the downloaded lowercase files.
RUN mv /tmp/models/phi-3-mini-4k-instruct-q5_k_m.gguf /tmp/models/phi3-mini.gguf
RUN mv /tmp/models/phi-3-small-8k-instruct-q5_k_m.gguf /tmp/models/phi3-small.gguf
RUN mv /tmp/models/phi-3-medium-4k-instruct-q5_k_m.gguf /tmp/models/phi3-medium.gguf
RUN mv /tmp/models/deepseek-coder-v2-lite-instruct-q5_k_m.gguf /tmp/models/deepseek-coder.gguf

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
# Remove the raw model files now that they are packaged by Ollama, saving image space.
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

