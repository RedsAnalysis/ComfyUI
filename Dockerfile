# Dockerfile for ComfyUI with Multi-Stage Build

# ==================================================================
# Build Arguments Definition
# ==================================================================
# Define build arguments with defaults (can be overridden by `docker build --build-arg`)
# Example default: Latest NVIDIA CUDA runtime
ARG BASE_IMAGE_TAG="nvidia/cuda:12.8.1-cudnn-runtime-ubuntu24.04"

# Define ARG for the FULL uv pip install command string for PyTorch.
# Example default: stable NVIDIA
ARG TORCH_INSTALL_ARGS="-p /app/venv/bin/python torch torchvision torchaudio --extra-index-url https://download.pytorch.org/whl/cu126"


# ==================================================================
# Stage 1: Base Environment Setup (OS, Python, UV, PyTorch)
# ==================================================================
# Use the selected base image tag passed via build-arg
FROM ${BASE_IMAGE_TAG} AS base

# Environment variables (Consistent across stages where needed)
ENV DEBIAN_FRONTEND=noninteractive
ENV UV_INSTALL_DIR="/root/.local/bin"
ENV UV_EXE="${UV_INSTALL_DIR}/uv"
ENV PYTHON_VERSION="3.12"
ENV VENV_PATH="/app/venv"
ENV VENV_PYTHON="${VENV_PATH}/bin/python"
# Update PATH to include venv and uv binaries. This will be inherited by subsequent stages.
ENV PATH="${VENV_PATH}/bin:${UV_INSTALL_DIR}:${PATH}"

# Re-declare ARGs needed within this stage for use in RUN commands
ARG TORCH_INSTALL_ARGS

# --- Install OS Dependencies & Python ---
# Install essential packages including python, git, curl, ffmpeg, and grep
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        git \
        curl \
        nano \
        "python${PYTHON_VERSION}" \
        "python${PYTHON_VERSION}-dev" \
        "python${PYTHON_VERSION}-venv" \
        wget \
        ffmpeg \
        libsm6 \
        libxext6 \
        libgl1 \
        grep \
    # Clean up apt cache to reduce layer size
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# --- Install and Verify UV ---
# Install the uv Python package manager from Astral
RUN echo "Installing uv..." \
    && curl -LsSf https://astral.sh/uv/install.sh | sh \
    && echo "Verifying uv installation..." \
    && ${UV_EXE} --version

# --- Create Virtual Environment & Install Core Tools ---
# Create the virtual environment where all Python packages will reside
RUN echo "Creating virtual environment with uv..." \
    && ${UV_EXE} venv ${VENV_PATH} --python "python${PYTHON_VERSION}" \
    # Ensure latest pip and wheel are installed within the venv
    && echo "Ensuring pip and wheel are installed/updated in venv..." \
    && ${UV_EXE} pip install -p ${VENV_PYTHON} --upgrade pip wheel \
    && echo "Verifying pip exists in venv:" \
    && ${VENV_PYTHON} -m pip --version

# --- Install PyTorch ---
# Install PyTorch into the virtual environment using the specific arguments
# provided by the TORCH_INSTALL_ARGS build argument.
# Doing this in the base stage improves Docker layer caching.
RUN echo "Installing PyTorch using command defined by TORCH_INSTALL_ARGS build-arg..." \
    && echo "  Executing: ${UV_EXE} pip install ${TORCH_INSTALL_ARGS}" \
    # TORCH_INSTALL_ARGS should contain the full command flags including target python, packages, and index URLs
    && ${UV_EXE} pip install ${TORCH_INSTALL_ARGS}

# --- Base stage is now complete with OS, Python, UV, Venv, and PyTorch ---


# ==================================================================
# Stage 2: Builder (Clone Repos, Install App Dependencies)
# ==================================================================
# Start the builder stage from the completed base stage
FROM base AS builder

# Set the working directory for cloning repositories
WORKDIR /build

# --- Clone Repositories ---
# Clone ComfyUI and ComfyUI-Manager. Use --depth 1 for faster clones (no history).
RUN echo "Cloning ComfyUI..." \
    && git clone --depth 1 https://github.com/RedsAnalysis/ComfyUI.git comfyui \
    && echo "Cloning ComfyUI-Manager..." \
    && git clone --depth 1 https://github.com/ltdrdata/ComfyUI-Manager.git comfyui/custom_nodes/ComfyUI-Manager

# --- Filter and Install Application Requirements ---
# Install Python dependencies for ComfyUI and the Manager into the venv created in the base stage.
RUN echo "Filtering ComfyUI requirements.txt to remove potential torch conflicts..." \
    # Use grep to create a filtered requirements file excluding torch, torchvision, torchaudio
    && grep -vE '^torch(vision|audio)?(=|<|>)?' /build/comfyui/requirements.txt > /build/comfyui/requirements.filtered.txt \
    && REQS_FILE="/build/comfyui/requirements.filtered.txt" \
    && echo "Installing ComfyUI filtered requirements from ${REQS_FILE}..." \
    # Install the filtered requirements using uv, targeting the venv
    && ${UV_EXE} pip install -p ${VENV_PYTHON} -r ${REQS_FILE} \
    # Explicitly install any other base dependencies not always in requirements (adjust as needed)
    && echo "Installing pyyaml and torchsde..." \
    && ${UV_EXE} pip install -p ${VENV_PYTHON} pyyaml torchsde \
    # Install requirements for ComfyUI-Manager if its requirements file exists
    && echo "Installing ComfyUI-Manager requirements..." \
    && MANAGER_REQS="/build/comfyui/custom_nodes/ComfyUI-Manager/requirements.txt" \
    && if [ -f "${MANAGER_REQS}" ]; then \
         ${UV_EXE} pip install -p ${VENV_PYTHON} -r ${MANAGER_REQS}; \
       else \
         echo "ComfyUI-Manager requirements.txt not found, skipping install."; \
       fi
        # --- Prepare Default Custom Nodes Staging Area ---
RUN mkdir -p /build/custom_nodes_defaults && \
cp -a /build/comfyui/custom_nodes/. /build/custom_nodes_defaults/

# --- Builder stage is complete. It contains the source code and installed dependencies in the venv. ---


# ==================================================================
# Stage 3: Final Image (Copy only necessary artifacts)
# ==================================================================
# Start the final stage from the base stage (which has OS, Python, UV, Venv base, PyTorch)
FROM base AS final

# Set the final working directory for the application
WORKDIR /app

# --- Copy Virtual Environment ---
COPY --from=builder ${VENV_PATH} ${VENV_PATH}

# --- Copy Defaults Staging Area --- Correct, only copy custom_nodes_defaults
COPY --from=builder /build/custom_nodes_defaults /app/comfyui/custom_nodes_defaults/

# --- Copy Application Code ---
# Core execution and server files
COPY --from=builder /build/comfyui/main.py /app/comfyui/
COPY --from=builder /build/comfyui/server.py /app/comfyui/
COPY --from=builder /build/comfyui/execution.py /app/comfyui/
COPY --from=builder /build/comfyui/nodes.py /app/comfyui/
COPY --from=builder /build/comfyui/node_helpers.py /app/comfyui/
COPY --from=builder /build/comfyui/comfyui_version.py /app/comfyui/
COPY --from=builder /build/comfyui/latent_preview.py /app/comfyui/
COPY --from=builder /build/comfyui/cuda_malloc.py /app/comfyui/
COPY --from=builder /build/comfyui/folder_paths.py /app/comfyui/

# Core library directories
COPY --from=builder /build/comfyui/comfy /app/comfyui/comfy/
COPY --from=builder /build/comfyui/comfy_extras /app/comfyui/comfy_extras/
COPY --from=builder /build/comfyui/comfy_api_nodes /app/comfyui/comfy_api_nodes/
COPY --from=builder /build/comfyui/comfy_execution /app/comfyui/comfy_execution/

# Web UI Assets (Located in 'app' directory)
COPY --from=builder /build/comfyui/app /app/comfyui/app/

# Supporting Python modules and files
COPY --from=builder /build/comfyui/utils /app/comfyui/utils/
COPY --from=builder /build/comfyui/api_server /app/comfyui/api_server/

# Copy ComfyUI-Manager node specifically
COPY --from=builder /build/comfyui/custom_nodes /app/comfyui/custom_nodes/

# Copy the entrypoint script (This file must exist next to the Dockerfile)
COPY doc-entrypoint.sh /app/doc-entrypoint.sh
# Make the entrypoint script executable
RUN chmod +x /app/doc-entrypoint.sh

# --- Final Runtime Setup ---
# Expose the port ComfyUI listens on
EXPOSE 8188

# Add a healthcheck to monitor if the ComfyUI service is responsive
HEALTHCHECK --interval=15s --timeout=5s --start-period=30s --retries=3 \
  CMD curl --fail http://localhost:8188/ || exit 1

# Set the entrypoint to our custom script.
# The CMD will be passed as arguments ($@) to the entrypoint script.
ENTRYPOINT ["/app/doc-entrypoint.sh"]

# Define the default command to be executed by the entrypoint script.
# This starts the ComfyUI server.
CMD ["python", "/app/comfyui/main.py", "--listen", "0.0.0.0", "--port", "8188"]

# --- Final image build is complete ---