#!/bin/bash

# Aiex Container Image Build Script
# Builds optimized container images for Kubernetes deployment

set -euo pipefail

# Configuration
IMAGE_NAME="aiex"
IMAGE_REGISTRY="${IMAGE_REGISTRY:-docker.io}"
IMAGE_REPOSITORY="${IMAGE_REPOSITORY:-aiex/aiex}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
DOCKERFILE="${DOCKERFILE:-Dockerfile.k8s}"
BUILD_CONTEXT="${BUILD_CONTEXT:-.}"
PLATFORM="${PLATFORM:-linux/amd64,linux/arm64}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

usage() {
    echo "Usage: $0 [OPTIONS] COMMAND"
    echo ""
    echo "Commands:"
    echo "  build      Build container image"
    echo "  push       Push image to registry"
    echo "  all        Build and push image"
    echo "  clean      Remove local images"
    echo ""
    echo "Options:"
    echo "  -t, --tag TAG               Image tag (default: latest)"
    echo "  -r, --registry REGISTRY     Container registry (default: docker.io)"
    echo "  -n, --name NAME             Image name (default: aiex/aiex)"
    echo "  -f, --dockerfile FILE       Dockerfile path (default: Dockerfile.k8s)"
    echo "  -p, --platform PLATFORMS    Target platforms (default: linux/amd64,linux/arm64)"
    echo "      --no-cache              Build without cache"
    echo "      --no-tui                Build without TUI component"
    echo "      --debug                 Enable debug output"
    echo "  -h, --help                  Show this help message"
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Docker is available
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed or not in PATH"
        exit 1
    fi
    
    # Check if Docker daemon is running
    if ! docker info &> /dev/null; then
        log_error "Docker daemon is not running"
        exit 1
    fi
    
    # Check if buildx is available for multi-platform builds
    if [[ "$PLATFORM" == *","* ]]; then
        if ! docker buildx version &> /dev/null; then
            log_error "Docker buildx is required for multi-platform builds"
            exit 1
        fi
        
        # Create builder instance if it doesn't exist
        if ! docker buildx ls | grep -q "aiex-builder"; then
            log_info "Creating buildx builder instance..."
            docker buildx create --name aiex-builder --use
        fi
    fi
    
    log_success "Prerequisites check passed"
}

build_image() {
    log_info "Building container image..."
    
    local full_image_name="$IMAGE_REGISTRY/$IMAGE_REPOSITORY:$IMAGE_TAG"
    local build_args=()
    
    # Add build arguments
    if [[ "${NO_TUI:-false}" == "true" ]]; then
        build_args+=(--target runtime)
    fi
    
    if [[ "${NO_CACHE:-false}" == "true" ]]; then
        build_args+=(--no-cache)
    fi
    
    if [[ "${DEBUG:-false}" == "true" ]]; then
        build_args+=(--progress=plain)
    fi
    
    # Build for multiple platforms or single platform
    if [[ "$PLATFORM" == *","* ]]; then
        log_info "Building multi-platform image for: $PLATFORM"
        docker buildx build \
            --platform "$PLATFORM" \
            --tag "$full_image_name" \
            --file "$DOCKERFILE" \
            "${build_args[@]}" \
            --load \
            "$BUILD_CONTEXT"
    else
        log_info "Building single-platform image for: $PLATFORM"
        docker build \
            --platform "$PLATFORM" \
            --tag "$full_image_name" \
            --file "$DOCKERFILE" \
            "${build_args[@]}" \
            "$BUILD_CONTEXT"
    fi
    
    log_success "Image built successfully: $full_image_name"
    
    # Show image info
    docker images "$IMAGE_REGISTRY/$IMAGE_REPOSITORY" | grep "$IMAGE_TAG"
}

push_image() {
    log_info "Pushing container image..."
    
    local full_image_name="$IMAGE_REGISTRY/$IMAGE_REPOSITORY:$IMAGE_TAG"
    
    # Check if image exists locally
    if ! docker images --format "table {{.Repository}}:{{.Tag}}" | grep -q "$full_image_name"; then
        log_error "Image $full_image_name not found locally. Build it first."
        exit 1
    fi
    
    # Push the image
    docker push "$full_image_name"
    
    log_success "Image pushed successfully: $full_image_name"
}

clean_images() {
    log_info "Cleaning up local images..."
    
    # Remove images with the same repository
    local images=$(docker images "$IMAGE_REGISTRY/$IMAGE_REPOSITORY" -q)
    
    if [[ -n "$images" ]]; then
        log_info "Removing images: $images"
        docker rmi $images
        log_success "Images removed"
    else
        log_info "No images found to remove"
    fi
}

validate_dockerfile() {
    log_info "Validating Dockerfile..."
    
    if [[ ! -f "$DOCKERFILE" ]]; then
        log_error "Dockerfile not found: $DOCKERFILE"
        exit 1
    fi
    
    # Basic Dockerfile validation
    if ! grep -q "FROM.*AS builder" "$DOCKERFILE"; then
        log_warning "Multi-stage build not detected in Dockerfile"
    fi
    
    if ! grep -q "USER.*aiex" "$DOCKERFILE"; then
        log_warning "Non-root user not found in Dockerfile"
    fi
    
    if ! grep -q "HEALTHCHECK" "$DOCKERFILE"; then
        log_warning "Health check not found in Dockerfile"
    fi
    
    log_success "Dockerfile validation completed"
}

show_image_info() {
    local full_image_name="$IMAGE_REGISTRY/$IMAGE_REPOSITORY:$IMAGE_TAG"
    
    log_info "Image information:"
    echo ""
    
    # Show image details
    docker inspect "$full_image_name" --format='
Image: {{.RepoTags}}
Created: {{.Created}}
Size: {{.Size}} bytes
Architecture: {{.Architecture}}
OS: {{.Os}}
Labels:
{{range $key, $value := .Config.Labels}}  {{$key}}: {{$value}}
{{end}}
Exposed Ports:
{{range $port, $obj := .Config.ExposedPorts}}  {{$port}}
{{end}}
' 2>/dev/null || log_warning "Could not inspect image (may not exist locally)"
}

# Parse command line arguments
NO_CACHE="false"
NO_TUI="false"
DEBUG="false"

while [[ $# -gt 0 ]]; do
    case $1 in
        -t|--tag)
            IMAGE_TAG="$2"
            shift 2
            ;;
        -r|--registry)
            IMAGE_REGISTRY="$2"
            shift 2
            ;;
        -n|--name)
            IMAGE_REPOSITORY="$2"
            shift 2
            ;;
        -f|--dockerfile)
            DOCKERFILE="$2"
            shift 2
            ;;
        -p|--platform)
            PLATFORM="$2"
            shift 2
            ;;
        --no-cache)
            NO_CACHE="true"
            shift
            ;;
        --no-tui)
            NO_TUI="true"
            shift
            ;;
        --debug)
            DEBUG="true"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        build|push|all|clean|info)
            COMMAND="$1"
            shift
            break
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Check if command is provided
if [[ -z "${COMMAND:-}" ]]; then
    log_error "No command specified"
    usage
    exit 1
fi

# Change to project root directory
cd "$(dirname "$0")/.."

# Execute command
case "$COMMAND" in
    build)
        check_prerequisites
        validate_dockerfile
        build_image
        show_image_info
        ;;
    push)
        check_prerequisites
        push_image
        ;;
    all)
        check_prerequisites
        validate_dockerfile
        build_image
        push_image
        show_image_info
        ;;
    clean)
        clean_images
        ;;
    info)
        show_image_info
        ;;
    *)
        log_error "Unknown command: $COMMAND"
        usage
        exit 1
        ;;
esac