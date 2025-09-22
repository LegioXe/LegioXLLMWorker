# llm-worker.Dockerfile (Final MVP Version)

# Start from the official, lean Ollama base image for reliability and small size.
FROM ollama/ollama

# Define the model to be pulled. 
# We are using the Q5_K_M quantization for the best quality-to-size ratio
# that can fit within the build limits of a standard GitHub runner.
ARG OLLAMA_MODEL_TAG=gpt-oss:20b-instruct-q5_k_m

# Pre-pull the specific model into the image during the build process.
# This ensures the model is "baked-in" and avoids cold starts on deployment.
RUN ollama pull ${OLLAMA_MODEL_TAG}

# Set up the final application environment.
WORKDIR /app

# Copy and install Python dependencies.
COPY llm-worker-requirements.txt .
RUN pip install --no-cache-dir -r llm-worker-requirements.txt

# Copy the application source code.
COPY worker_api.py .
COPY start.sh .
RUN chmod +x ./start.sh

# Expose the port the API will run on.
EXPOSE 8000

# Define the command to start the application at runtime.
CMD ["./start.sh"]
