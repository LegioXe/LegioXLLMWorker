# llm-worker.Dockerfile

# ARCHITECTURAL NOTE: Base Image Selection
# We start from an official RunPod PyTorch image. This is a critical choice because it provides a pre-configured, optimized environment
# with the correct NVIDIA drivers, CUDA toolkit, and PyTorch libraries. This saves significant build time and eliminates potential
# compatibility issues between the OS, the drivers, and the model serving framework.
#
FROM runpod/pytorch:2.2.0-py3.10-cuda12.1.1-devel-ubuntu22.04

LABEL maintainer="AIOS Project"
LABEL description="A high-performance LLM worker for AIOS, serving multiple models via Ollama. Models are pre-pulled to minimize cold starts."

#
# ARCHITECTURAL NOTE: Environment Configuration
# Setting environment variables makes the Dockerfile cleaner and easier to update. DEBIAN_FRONTEND prevents interactive prompts
# during package installation, which is essential for automated builds.
#
ENV DEBIAN_FRONTEND=noninteractive
# Define the models to be "baked" into the image. This is the core of the fast-start strategy.
ENV PHI3_MINI_MODEL=phi3:3.8b-mini-instruct-4k-q5_K_M
ENV PHI3_SMALL_MODEL=phi3:7b-small-instruct-4k-q5_K_M
ENV PHI3_MEDIUM_MODEL=phi3:14b-medium-instruct-4k-q5_K_M
ENV DEEPSEEK_CODER_MODEL=deepseek-coder-v2:16b-lite-instruct-q5_K_M

#
# STAGE 1: System & Ollama Installation
#
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

#
# --- Use the official Ollama installation script ---
# ARCHITECTURAL NOTE: Robust Installation
# Instead of downloading the binary directly (which can be brittle), we use the official
# installation script. This is the recommended approach as it handles system checks,
# permissions, and ensures the correct binary is placed in the right location.
#
RUN curl -fsSL https://ollama.com/install.sh | sh

#
# STAGE 2: Model Pulling (The "Baking" Process)
#
# ARCHITECTURAL NOTE: Pre-pulling Models for Performance
# This is the most important optimization in this file. By pulling the models during the Docker build process,
# the large model files become part of the image layers. When RunPod starts a new container, the models are already
# on the local disk, eliminating network download time from the cold start.
#
# We start the server in the background, pull each model sequentially, and then stop the server.
RUN /bin/bash -c 'ollama serve & sleep 5 && \
    echo "--- Pulling Phi-3 Mini (3.8B) ---" && \
    ollama pull ${PHI3_MINI_MODEL} && \
    echo "--- Pulling Phi-3 Small (7B) ---" && \
    ollama pull ${PHI3_SMALL_MODEL} && \
    echo "--- Pulling Phi-3 Medium (14B) ---" && \
    ollama pull ${PHI3_MEDIUM_MODEL} && \
    echo "--- Pulling DeepSeek Coder V2 Lite (16B) ---" && \
    ollama pull ${DEEPSEEK_CODER_MODEL} && \
    pkill ollama'

#
# STAGE 3: Application Setup
#
WORKDIR /app

# Copy and install Python dependencies.
COPY llm-worker-requirements.txt .
RUN pip install --no-cache-dir -r llm-worker-requirements.txt

# Copy the application code that will run the API server.
COPY worker_api.py .

#
# STAGE 4: Runtime Configuration
#
# Expose the port the application will run on.
EXPOSE 8000

# The command to start both the Ollama server and the FastAPI application.
COPY start.sh .
RUN chmod +x ./start.sh
CMD ["./start.sh"]
