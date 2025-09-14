#!/bin/bash
# Start the Ollama server in the background
ollama serve &

# Wait a few seconds for the server to be ready
sleep 3

# Start the FastAPI application in the foreground
uvicorn worker_api:app --host 0.0.0.0 --port 8000