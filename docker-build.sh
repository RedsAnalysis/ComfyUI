#!/bin/bash

set -e # Exit immediately if a command exits with a non-zero status.

# Define Python Version and Venv Path (must match Dockerfile ENV)
PYTHON_VERSION="3.12"
VENV_PATH="/app/venv"
VENV_PYTHON="${VENV_PATH}/bin/python"

# Function to display version information (No change needed)
display_version_info() {
    echo "==========================================================="
    echo " PyTorch Version Selection (determines base image & install args):"
    echo "-----------------------------------------------------------"
    echo " Stable Version:"
    echo "  - Thoroughly tested, recommended for general use."
    echo "-----------------------------------------------------------"
    echo " Latest Version (Nightly/Pre-release):"
    echo "  - Includes newest features and optimizations."
    echo "==========================================================="
}

# Function to ask user for GPU type (No change needed)
ask_gpu_type() {
    echo "Select GPU Type:"
    select gpu_choice in "NVIDIA" "AMD" "Cancel"; do
        case $gpu_choice in
            NVIDIA) gpu="NVIDIA"; echo "Selected: NVIDIA"; break ;;
            AMD) gpu="AMD"; echo "Selected: AMD"; break ;;
            Cancel) echo "Build cancelled."; exit 0 ;;
            *) echo "Invalid option $REPLY. Please choose 1, 2, or 3." ;;
        esac
    done
}

# Function to ask user for PyTorch version preference (No change needed)
# This now ONLY affects the base image and install args, NOT the final tag version.
ask_pytorch_preference() {
    echo "Select PyTorch Base (Stable or Latest/Nightly):"
    select version_choice in "Stable" "Latest" "Cancel"; do
        case $version_choice in
            Stable) pytorch_pref="Stable"; echo "Selected: Stable PyTorch Base"; break ;;
            Latest) pytorch_pref="Latest"; echo "Selected: Latest PyTorch Base"; break ;;
            Cancel) echo "Build cancelled."; exit 0 ;;
            *) echo "Invalid option $REPLY. Please choose 1, 2, or 3." ;;
        esac
    done
}

# *** NEW FUNCTION: Ask for the specific version tag ***
ask_version_tag() {
     while true; do
        # Prompt the user for the version tag
        read -p "Enter the desired image version tag (e.g., v0.3.30): " IMAGE_VERSION_TAG
        # Check if the input is not empty
        if [[ -n "$IMAGE_VERSION_TAG" ]]; then
            # Basic check to avoid tags starting or ending with : or / (can be refined)
            if [[ ! "$IMAGE_VERSION_TAG" =~ ^[:/] || ! "$IMAGE_VERSION_TAG" =~ [:/]$ ]]; then
                echo "Using image version tag: ${IMAGE_VERSION_TAG}"
                break # Exit the loop if input is valid
            else
                echo "Error: Invalid characters used in tag. Avoid starting/ending with ':' or '/'."
            fi
        else
            echo "Error: Version tag cannot be empty. Please try again."
        fi
    done
}

# --- Main Script Logic ---

display_version_info
ask_gpu_type
ask_pytorch_preference # Ask for Stable/Latest PyTorch base
ask_version_tag        # Ask for the specific version tag (e.g., v0.3.30)

# --- Determine Build Arguments based on PyTorch Preference ---
echo "Configuring build arguments based on PyTorch preference (${pytorch_pref})..."

if [[ "$gpu" == "NVIDIA" ]]; then
    if [[ "$pytorch_pref" == "Stable" ]]; then
        BASE_IMAGE_TAG="nvidia/cuda:12.6.3-cudnn-runtime-ubuntu24.04"
        TORCH_INSTALL_ARGS="-p ${VENV_PYTHON} torch torchvision torchaudio --extra-index-url https://download.pytorch.org/whl/cu126"
    else # Latest
        BASE_IMAGE_TAG="nvidia/cuda:12.8.1-cudnn-runtime-ubuntu24.04"
        TORCH_INSTALL_ARGS="-p ${VENV_PYTHON} --pre torch torchvision torchaudio --index-url https://download.pytorch.org/whl/nightly/cu128"
    fi
elif [[ "$gpu" == "AMD" ]]; then
     if [[ "$pytorch_pref" == "Stable" ]]; then
        BASE_IMAGE_TAG="rocm/dev-ubuntu-24.04:6.2.4-complete"
        TORCH_INSTALL_ARGS="-p ${VENV_PYTHON} torch torchvision torchaudio --index-url https://download.pytorch.org/whl/rocm6.2"
    else # Latest
        BASE_IMAGE_TAG="rocm/dev-ubuntu-24.04:6.3.4-complete"
        TORCH_INSTALL_ARGS="-p ${VENV_PYTHON} --pre torch torchvision torchaudio --index-url https://download.pytorch.org/whl/nightly/rocm6.3"
    fi
else
    echo "Error: Invalid GPU type configured."
    exit 1
fi

# --- Construct the Docker Image Name PARTS ---
IMAGE_BASE_NAME="comfyui-${gpu,,}" # e.g., comfyui-nvidia
# IMAGE_VERSION_TAG is already set by ask_version_tag

# --- Construct the Full Image Name with Tag for the build command ---
FULL_IMAGE_NAME_WITH_TAG="${IMAGE_BASE_NAME}:${IMAGE_VERSION_TAG}" # e.g., comfyui-nvidia:v0.3.30

echo "-----------------------------------------------------------"
echo "Starting Docker build..."
echo "  Image Name + Tag: ${FULL_IMAGE_NAME_WITH_TAG}" # Correctly shows name:tag
echo "  Base Image: ${BASE_IMAGE_TAG}"
echo "  PyTorch Args: ${TORCH_INSTALL_ARGS}"
echo "-----------------------------------------------------------"

# Build the image using Docker build arguments
# Use --no-cache if you want to force a full rebuild without using cache layers
docker build \
    --no-cache \
    --build-arg BASE_IMAGE_TAG="${BASE_IMAGE_TAG}" \
    --build-arg TORCH_INSTALL_ARGS="${TORCH_INSTALL_ARGS}" \
    -t "${FULL_IMAGE_NAME_WITH_TAG}" \
    -f Dockerfile .

BUILD_STATUS=$? # Capture exit status of docker build

echo "-----------------------------------------------------------"
if [ $BUILD_STATUS -eq 0 ]; then
    echo "Docker build successful!"
    echo "Image created: ${FULL_IMAGE_NAME_WITH_TAG}" # Correct variable
    echo ""
    # Correct variable used in the instruction message
    echo "IMPORTANT: Update the 'image:' tag in your docker-compose.yml to '${FULL_IMAGE_NAME_WITH_TAG}' before running:" # <--- CORRECTED variable
    echo "  docker-compose up -d"
    echo ""
    echo "To stop the container:"
    echo "  docker-compose down"
else
    echo "Docker build failed with status: ${BUILD_STATUS}"
fi
echo "==========================================================="

exit $BUILD_STATUS