#!/bin/bash
set -e # Exit immediately if a command exits with a non-zero status.

# Define paths within the container
APP_DIR="/app/comfyui"
CUSTOM_NODES_DEFAULTS_SRC="${APP_DIR}/custom_nodes_defaults" # Source of defaults baked into the image
CUSTOM_NODES_TARGET="${APP_DIR}/custom_nodes"                # Target host mount point
MANAGER_DIR_NAME="ComfyUI-Manager"                           # Name of the manager directory
MODELS_TARGET="${APP_DIR}/models"                            # Target host mount point
INPUT_TARGET="${APP_DIR}/input"                              # Target host mount point
OUTPUT_TARGET="${APP_DIR}/output"                            # Target host mount point
USER_TARGET="${APP_DIR}/user"                                # Target host mount point

echo "--- ComfyUI Docker Entrypoint Script ---"

# --- Initialize Host Directories (Base Creation) ---

# Function to check and create directory if needed
# Returns 0 if directory existed, 1 if it was created by this function
ensure_host_dir() {
  local target_path="$1"
  local dir_name="$2"
  if [ -d "${target_path}" ]; then
    echo "INFO: ${dir_name} directory (${target_path}) found on container start."
    return 0 # Indicates directory existed when script checked
  else
    # This case might be rare if Docker Compose always creates it first, but good to handle
    echo "INFO: ${dir_name} directory (${target_path}) not found on container start, creating..."
    mkdir -p "${target_path}"
    return 1 # Indicates directory was created by script
  fi
}

# Ensure base directories exist
ensure_host_dir "${INPUT_TARGET}" "Input"
ensure_host_dir "${OUTPUT_TARGET}" "Output"
USER_DIR_STATUS=$(ensure_host_dir "${USER_TARGET}" "User" >&2; echo $?) # Capture status, redirect echo to stderr
if [ ${USER_DIR_STATUS} -ne 0 ]; then
    echo "INFO: User directory created by doc-entrypoint/compose. ComfyUI will populate it with defaults if necessary on first run."
fi
MODELS_DIR_STATUS=$(ensure_host_dir "${MODELS_TARGET}" "Models" >&2; echo $?)
CUSTOM_NODES_DIR_STATUS=$(ensure_host_dir "${CUSTOM_NODES_TARGET}" "Custom Nodes" >&2; echo $?)


# --- Handle Custom Nodes Initialization ---
echo "INFO: Processing Custom Nodes directory..."

if [ ${CUSTOM_NODES_DIR_STATUS} -ne 0 ]; then
    # Base directory was effectively newly created (return code 1)
    echo "INFO: Custom Nodes directory appears newly created."
    if [ -d "${CUSTOM_NODES_DEFAULTS_SRC}" ] && [ "$(ls -A ${CUSTOM_NODES_DEFAULTS_SRC})" ]; then
        echo "INFO: Copying full default custom_nodes contents (Manager, examples)..."
        cp -a "${CUSTOM_NODES_DEFAULTS_SRC}/." "${CUSTOM_NODES_TARGET}/"
        echo "INFO: Default custom_nodes copied into ${CUSTOM_NODES_TARGET}."
    else
        echo "WARN: Source defaults '${CUSTOM_NODES_DEFAULTS_SRC}' not found or empty. Cannot initialize."
    fi
else
    # Base directory already existed (return code 0)
    echo "INFO: Custom Nodes directory pre-existed. Checking for ${MANAGER_DIR_NAME}..."
    if [ ! -d "${CUSTOM_NODES_TARGET}/${MANAGER_DIR_NAME}" ]; then
        # Manager directory is missing
        echo "WARN: '${MANAGER_DIR_NAME}' not found in existing Custom Nodes directory."
        if [ -d "${CUSTOM_NODES_DEFAULTS_SRC}/${MANAGER_DIR_NAME}" ]; then
            echo "INFO: Copying ONLY '${MANAGER_DIR_NAME}' from image defaults..."
            cp -a "${CUSTOM_NODES_DEFAULTS_SRC}/${MANAGER_DIR_NAME}" "${CUSTOM_NODES_TARGET}/"
            echo "INFO: '${MANAGER_DIR_NAME}' copied into ${CUSTOM_NODES_TARGET}."
        else
            echo "ERROR: Default '${MANAGER_DIR_NAME}' not found in '${CUSTOM_NODES_DEFAULTS_SRC}'. Cannot copy."
        fi
    else
        # Manager directory exists
        echo "INFO: '${MANAGER_DIR_NAME}' found. Skipping default copy. User can update via ComfyUI if needed."
    fi
fi

# --- Initialize Models Directory Structure ---
if [ ${MODELS_DIR_STATUS} -ne 0 ]; then
    echo "INFO: Models directory created by doc-entrypoint/compose, ensuring structure..."
else
    echo "INFO: Models directory pre-existed, ensuring structure..."
fi

MODEL_SUBDIRS=(
    "checkpoints" "clip" "clip_vision" "configs" "controlnet" "diffusers" "diffusion_models"
    "embeddings" "gligen" "hypernetworks" "loras" "photomaker" "style_models"
    "text_encoders" "unet" "upscale_models" "vae" "vae_approx"
)
for subdir in "${MODEL_SUBDIRS[@]}"; do
    mkdir -p "${MODELS_TARGET}/${subdir}"
done
echo "INFO: Model subdirectory structure ensured."

# --- Execute the main command ---
echo "INFO: Starting ComfyUI..."
exec "$@"