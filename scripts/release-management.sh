#!/bin/bash

# Aiex Release Management Script
# Comprehensive release orchestration for distributed deployments

set -euo pipefail

# Configuration
RELEASE_DIR="$(dirname "$0")/.."
BUILD_DIR="$RELEASE_DIR/_build"
RELEASE_NAME="aiex"
DOCKER_REGISTRY="${DOCKER_REGISTRY:-docker.io}"
DOCKER_REPOSITORY="${DOCKER_REPOSITORY:-aiex/aiex}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
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

# Function to display usage
usage() {
    echo "Usage: $0 [COMMAND] [OPTIONS]"
    echo ""
    echo "Commands:"
    echo "  build                    Build Mix release"
    echo "  container               Build container image"
    echo "  deploy                  Deploy to cluster"
    echo "  rollback                Rollback to previous version"
    echo "  health                  Check cluster health"
    echo "  status                  Get deployment status"
    echo "  cleanup                 Clean up old releases"
    echo ""
    echo "Options:"
    echo "  -v, --version VERSION   Release version (default: auto-generated)"
    echo "  -e, --env ENVIRONMENT   Target environment (default: production)"
    echo "  -s, --strategy STRATEGY Deployment strategy (blue_green|rolling|canary)"
    echo "  -t, --timeout TIMEOUT   Deployment timeout in seconds (default: 300)"
    echo "      --dry-run           Show what would be done without executing"
    echo "      --force             Force deployment without health checks"
    echo "      --auto-rollback     Enable automatic rollback on failure"
    echo "  -h, --help              Show this help message"
}

# Parse command line arguments
COMMAND=""
VERSION=""
ENVIRONMENT="production"
STRATEGY="rolling_update"
TIMEOUT="300"
DRY_RUN="false"
FORCE="false"
AUTO_ROLLBACK="false"

while [[ $# -gt 0 ]]; do
    case $1 in
        build|container|deploy|rollback|health|status|cleanup)
            COMMAND="$1"
            shift
            ;;
        -v|--version)
            VERSION="$2"
            shift 2
            ;;
        -e|--env)
            ENVIRONMENT="$2"
            shift 2
            ;;
        -s|--strategy)
            STRATEGY="$2"
            shift 2
            ;;
        -t|--timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        --dry-run)
            DRY_RUN="true"
            shift
            ;;
        --force)
            FORCE="true"
            shift
            ;;
        --auto-rollback)
            AUTO_ROLLBACK="true"
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

# Validate command
if [[ -z "$COMMAND" ]]; then
    log_error "No command specified"
    usage
    exit 1
fi

# Change to project directory
cd "$RELEASE_DIR"

# Generate version if not provided
if [[ -z "$VERSION" ]]; then
    if [[ -f "VERSION" ]]; then
        VERSION=$(cat VERSION)
    else
        # Generate version from git or timestamp
        if git rev-parse --git-dir > /dev/null 2>&1; then
            VERSION="$(git describe --tags --always --dirty)-$(date +%Y%m%d%H%M%S)"
        else
            VERSION="dev-$(date +%Y%m%d%H%M%S)"
        fi
    fi
fi

log_info "Release management for $RELEASE_NAME version $VERSION"
log_info "Environment: $ENVIRONMENT, Strategy: $STRATEGY"

# Helper functions

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if Mix is available
    if ! command -v mix &> /dev/null; then
        log_error "Mix is not installed or not in PATH"
        exit 1
    fi
    
    # Check if Docker is available (for container builds)
    if [[ "$COMMAND" == "container" ]] && ! command -v docker &> /dev/null; then
        log_error "Docker is not installed or not in PATH"
        exit 1
    fi
    
    # Check if kubectl is available (for deployments)
    if [[ "$COMMAND" == "deploy" ]] && ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed or not in PATH"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

build_release() {
    log_info "Building Mix release..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would build release with: MIX_ENV=$ENVIRONMENT mix release"
        return 0
    fi
    
    # Clean previous builds
    if [[ -d "$BUILD_DIR" ]]; then
        log_info "Cleaning previous builds..."
        rm -rf "$BUILD_DIR"
    fi
    
    # Get dependencies
    log_info "Getting dependencies..."
    MIX_ENV="$ENVIRONMENT" mix deps.get --only="$ENVIRONMENT"
    
    # Compile project
    log_info "Compiling project..."
    MIX_ENV="$ENVIRONMENT" mix compile
    
    # Build release
    log_info "Building release..."
    MIX_ENV="$ENVIRONMENT" mix release
    
    # Verify release
    release_path="$BUILD_DIR/$ENVIRONMENT/rel/$RELEASE_NAME"
    if [[ -d "$release_path" ]]; then
        log_success "Release built successfully at $release_path"
        
        # Show release info
        log_info "Release information:"
        echo "  Version: $VERSION"
        echo "  Environment: $ENVIRONMENT"
        echo "  Path: $release_path"
        echo "  Size: $(du -sh "$release_path" | cut -f1)"
    else
        log_error "Release build failed - release directory not found"
        exit 1
    fi
}

build_container() {
    log_info "Building container image..."
    
    local image_tag="$DOCKER_REGISTRY/$DOCKER_REPOSITORY:$VERSION"
    local latest_tag="$DOCKER_REGISTRY/$DOCKER_REPOSITORY:latest"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would build container: $image_tag"
        return 0
    fi
    
    # Build container using the build script
    if [[ -f "k8s/build.sh" ]]; then
        log_info "Using k8s/build.sh for container build..."
        ./k8s/build.sh build --tag "$VERSION"
    else
        log_info "Building container directly with Docker..."
        
        # Build multi-stage container
        docker build \
            --tag "$image_tag" \
            --tag "$latest_tag" \
            --build-arg VERSION="$VERSION" \
            --build-arg ENVIRONMENT="$ENVIRONMENT" \
            --file Dockerfile.k8s \
            .
    fi
    
    log_success "Container built: $image_tag"
    
    # Show image info
    docker images "$DOCKER_REPOSITORY" | grep "$VERSION"
}

deploy_release() {
    log_info "Deploying release to $ENVIRONMENT..."
    
    # Pre-deployment checks
    if [[ "$FORCE" != "true" ]]; then
        log_info "Performing pre-deployment health checks..."
        if ! check_cluster_health; then
            log_error "Cluster health check failed. Use --force to override."
            exit 1
        fi
    fi
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would deploy with strategy: $STRATEGY"
        log_info "[DRY RUN] Target version: $VERSION"
        log_info "[DRY RUN] Timeout: ${TIMEOUT}s"
        return 0
    fi
    
    case "$STRATEGY" in
        "blue_green")
            deploy_blue_green
            ;;
        "rolling_update"|"rolling")
            deploy_rolling_update
            ;;
        "canary")
            deploy_canary
            ;;
        *)
            log_error "Unknown deployment strategy: $STRATEGY"
            exit 1
            ;;
    esac
}

deploy_blue_green() {
    log_info "Starting blue-green deployment..."
    
    # Update Kubernetes deployment with new image
    local image_tag="$DOCKER_REGISTRY/$DOCKER_REPOSITORY:$VERSION"
    
    log_info "Updating deployment image to $image_tag..."
    kubectl set image deployment/aiex aiex="$image_tag" -n aiex
    
    # Wait for rollout to complete
    log_info "Waiting for rollout to complete..."
    kubectl rollout status deployment/aiex -n aiex --timeout="${TIMEOUT}s"
    
    # Verify deployment
    verify_deployment
    
    log_success "Blue-green deployment completed successfully"
}

deploy_rolling_update() {
    log_info "Starting rolling update deployment..."
    
    local image_tag="$DOCKER_REGISTRY/$DOCKER_REPOSITORY:$VERSION"
    
    # Update deployment
    log_info "Updating deployment image to $image_tag..."
    kubectl set image deployment/aiex aiex="$image_tag" -n aiex
    
    # Monitor rolling update
    log_info "Monitoring rolling update progress..."
    kubectl rollout status deployment/aiex -n aiex --timeout="${TIMEOUT}s"
    
    # Verify deployment
    verify_deployment
    
    log_success "Rolling update completed successfully"
}

deploy_canary() {
    log_info "Starting canary deployment..."
    
    # This would implement canary deployment logic
    # For now, fall back to rolling update
    log_warning "Canary deployment not fully implemented, using rolling update"
    deploy_rolling_update
}

verify_deployment() {
    log_info "Verifying deployment..."
    
    # Check pod status
    log_info "Checking pod status..."
    kubectl get pods -n aiex -l app=aiex
    
    # Check service endpoints
    log_info "Checking service endpoints..."
    kubectl get endpoints -n aiex
    
    # Perform health check
    if check_deployment_health; then
        log_success "Deployment verification passed"
    else
        log_error "Deployment verification failed"
        
        if [[ "$AUTO_ROLLBACK" == "true" ]]; then
            log_warning "Auto-rollback enabled, rolling back deployment..."
            rollback_deployment
        fi
        
        exit 1
    fi
}

check_cluster_health() {
    log_info "Checking cluster health..."
    
    # Check if kubectl can connect
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster"
        return 1
    fi
    
    # Check namespace exists
    if ! kubectl get namespace aiex &> /dev/null; then
        log_error "Aiex namespace does not exist"
        return 1
    fi
    
    # Check if deployment exists
    if ! kubectl get deployment aiex -n aiex &> /dev/null; then
        log_warning "Aiex deployment does not exist (this might be the first deployment)"
        return 0
    fi
    
    # Check current deployment status
    local ready_replicas
    ready_replicas=$(kubectl get deployment aiex -n aiex -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    local desired_replicas
    desired_replicas=$(kubectl get deployment aiex -n aiex -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "1")
    
    if [[ "$ready_replicas" -lt "$desired_replicas" ]]; then
        log_error "Not all replicas are ready ($ready_replicas/$desired_replicas)"
        return 1
    fi
    
    log_success "Cluster health check passed"
    return 0
}

check_deployment_health() {
    log_info "Checking deployment health..."
    
    # Wait a bit for pods to start
    sleep 10
    
    # Check if all pods are ready
    local ready_pods
    ready_pods=$(kubectl get pods -n aiex -l app=aiex -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}' | tr ' ' '\n' | grep -c "True" || echo "0")
    local total_pods
    total_pods=$(kubectl get pods -n aiex -l app=aiex -o jsonpath='{.items[*].metadata.name}' | wc -w)
    
    if [[ "$ready_pods" -ne "$total_pods" ]]; then
        log_error "Not all pods are ready ($ready_pods/$total_pods)"
        return 1
    fi
    
    # Try to connect to health endpoint
    local health_url
    health_url=$(kubectl get service aiex -n aiex -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    
    if [[ -n "$health_url" ]]; then
        log_info "Testing health endpoint at $health_url..."
        if curl -f --max-time 10 "http://$health_url:8090/health" &> /dev/null; then
            log_success "Health endpoint responding"
        else
            log_warning "Health endpoint not responding"
            return 1
        fi
    else
        log_info "Service IP not yet available, skipping health endpoint test"
    fi
    
    log_success "Deployment health check passed"
    return 0
}

rollback_deployment() {
    log_info "Rolling back deployment..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would rollback deployment"
        return 0
    fi
    
    # Get previous revision
    local previous_revision
    previous_revision=$(kubectl rollout history deployment/aiex -n aiex | tail -n 2 | head -n 1 | awk '{print $1}')
    
    if [[ -n "$previous_revision" ]]; then
        log_info "Rolling back to revision $previous_revision..."
        kubectl rollout undo deployment/aiex -n aiex --to-revision="$previous_revision"
        
        # Wait for rollback to complete
        kubectl rollout status deployment/aiex -n aiex --timeout="${TIMEOUT}s"
        
        log_success "Rollback completed"
    else
        log_error "No previous revision found for rollback"
        exit 1
    fi
}

get_deployment_status() {
    log_info "Getting deployment status..."
    
    # Deployment status
    echo "Deployment Status:"
    kubectl get deployment aiex -n aiex -o wide
    
    echo ""
    echo "Pod Status:"
    kubectl get pods -n aiex -l app=aiex -o wide
    
    echo ""
    echo "Service Status:"
    kubectl get services -n aiex
    
    echo ""
    echo "Recent Events:"
    kubectl get events -n aiex --sort-by='.lastTimestamp' | tail -10
}

cleanup_old_releases() {
    log_info "Cleaning up old releases..."
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY RUN] Would clean up old releases"
        return 0
    fi
    
    # Clean up old container images (keep last 5 versions)
    log_info "Cleaning up old container images..."
    docker images "$DOCKER_REPOSITORY" --format "table {{.Tag}}\t{{.CreatedAt}}" | \
        grep -v "latest" | grep -v "TAG" | sort -k2 | head -n -5 | \
        awk '{print $1}' | while read -r tag; do
            if [[ -n "$tag" && "$tag" != "<none>" ]]; then
                log_info "Removing old image: $DOCKER_REPOSITORY:$tag"
                docker rmi "$DOCKER_REPOSITORY:$tag" || true
            fi
        done
    
    # Clean up old Kubernetes rollout history (keep last 3 revisions)
    log_info "Cleaning up old rollout history..."
    kubectl patch deployment aiex -n aiex -p '{"spec":{"revisionHistoryLimit":3}}'
    
    log_success "Cleanup completed"
}

# Main execution
main() {
    log_info "Starting $COMMAND operation..."
    
    check_prerequisites
    
    case "$COMMAND" in
        "build")
            build_release
            ;;
        "container")
            build_container
            ;;
        "deploy")
            deploy_release
            ;;
        "rollback")
            rollback_deployment
            ;;
        "health")
            check_cluster_health && log_success "Cluster is healthy"
            ;;
        "status")
            get_deployment_status
            ;;
        "cleanup")
            cleanup_old_releases
            ;;
        *)
            log_error "Unknown command: $COMMAND"
            usage
            exit 1
            ;;
    esac
    
    log_success "Operation completed successfully"
}

# Run main function
main "$@"