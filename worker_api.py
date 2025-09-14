# worker_api.py

#
# ARCHITECTURAL NOTE: API Framework and Purpose
# This script uses FastAPI to create a minimal, high-performance API server. Its sole responsibility
# is to act as a clean interface between the external network (the LLM Router) and the Ollama
# service running inside the same container. It is designed to be completely stateless, making it
# perfectly suited for a serverless environment where instances can be created and destroyed on demand.
#
import logging
import requests
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

# --- Logging Setup ---
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(name)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

#
# ARCHITECTURAL NOTE: Internal Communication
# The OLLAMA_URL is set to 127.0.0.1 (localhost). This is because both this FastAPI
# application and the Ollama server are running as separate processes inside the *same* container.
# This allows for fast and secure communication without needing to traverse an external network.
#
OLLAMA_URL = "http://127.0.0.1:11434/api/generate"

# --- Pydantic Models for a Typed API ---
# Using Pydantic models ensures that all incoming requests are validated against a schema,
# preventing common errors and improving the API's robustness.

class GenerateRequest(BaseModel):
    """Defines the input structure for an LLM generation request."""
    model: str = Field(..., description="The name of the Ollama model to use (e.g., 'phi3:7b-small-instruct-4k-q5_K_M').")
    prompt: str = Field(..., description="The user's full prompt text.")

class GenerateResponse(BaseModel):
    """Defines the output structure for a successful LLM generation."""
    response_text: str

# --- FastAPI App Initialization ---
app = FastAPI(
    title="AIOS LLM Worker",
    description="A stateless worker that serves multiple LLMs via an internal Ollama instance."
)

# --- API Endpoints ---

@app.get("/health")
async def health_check():
    """
    A simple health check endpoint.
    
    This allows the orchestrator (like RunPod) to verify that the API server
    is running and responsive before routing traffic to it.
    """
    logger.info("Health check endpoint was called.")
    return {"status": "ok"}


@app.post("/generate", response_model=GenerateResponse)
async def generate_llm_response(request: GenerateRequest):
    """
    The primary endpoint for generating text from a specified language model.

    This function receives a prompt and a model name, forwards the request to the
    local Ollama server, and returns the generated text.
    """
    logger.info(f"Received generation request for model: {request.model}")

    #
    # ARCHITECTURAL NOTE: Synchronous, Non-Streaming Request
    # We set `stream: false` in the payload to Ollama. This means we wait for the
    # entire response to be generated before sending it back. For the AIOS system's
    # sequential, task-oriented LangGraph nodes, this is the ideal approach as each
    # node typically requires the full output before it can proceed. Streaming would add
    # unnecessary complexity to this worker's client (the LLM Router).
    #
    payload = {
        "model": request.model,
        "prompt": request.prompt,
        "stream": False
    }

    try:
        # We use the standard `requests` library for this internal, synchronous call.
        response = requests.post(OLLAMA_URL, json=payload, timeout=300) # 5-minute timeout for long generations
        response.raise_for_status() # Raises an exception for bad status codes (4xx or 5xx)

        response_data = response.json()
        final_text = response_data.get("response", "")

        logger.info(f"Successfully generated response from model: {request.model}")
        return GenerateResponse(response_text=final_text)

    except requests.exceptions.RequestException as e:
        logger.error(f"Error communicating with Ollama: {e}", exc_info=True)
        raise HTTPException(status_code=503, detail=f"Could not communicate with the internal Ollama service: {e}")
    except Exception as e:
        logger.error(f"An unexpected error occurred during generation: {e}", exc_info=True)
        raise HTTPException(status_code=500, detail=f"An internal error occurred: {e}")