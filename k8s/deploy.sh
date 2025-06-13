#!/bin/bash

# Aiex Kubernetes Deployment Script
# This script deploys Aiex to a Kubernetes cluster using either kubectl or Helm

set -euo pipefail

# Configuration
NAMESPACE="aiex"
RELEASE_NAME="aiex"
CHART_PATH="helm/aiex"
MANIFESTS_PATH="manifests"

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
    echo "  helm       Deploy using Helm chart"
    echo "  kubectl    Deploy using kubectl manifests"
    echo "  delete     Delete the deployment"
    echo "  status     Check deployment status"
    echo "  logs       View application logs"
    echo ""
    echo "Options:"
    echo "  -n, --namespace NAMESPACE    Kubernetes namespace (default: aiex)"
    echo "  -r, --release RELEASE        Helm release name (default: aiex)"
    echo "  -f, --values-file FILE       Additional Helm values file"
    echo "  -d, --dry-run               Perform a dry run"
    echo "  --debug                     Enable debug output"
    echo "  -h, --help                  Show this help message"
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if kubectl is available
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed or not in PATH"
        exit 1
    fi
    
    # Check if cluster is accessible
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster"
        exit 1
    fi
    
    log_success "Prerequisites check passed"
}

create_namespace() {
    log_info "Creating namespace: $NAMESPACE"
    
    if kubectl get namespace "$NAMESPACE" &> /dev/null; then
        log_warning "Namespace $NAMESPACE already exists"
    else
        kubectl create namespace "$NAMESPACE"
        log_success "Namespace $NAMESPACE created"
    fi
}

deploy_with_helm() {
    log_info "Deploying Aiex using Helm..."
    
    # Check if Helm is available
    if ! command -v helm &> /dev/null; then
        log_error "Helm is not installed or not in PATH"
        exit 1
    fi
    
    create_namespace
    
    # Build Helm command
    HELM_CMD="helm upgrade --install $RELEASE_NAME $CHART_PATH"
    HELM_CMD="$HELM_CMD --namespace $NAMESPACE"
    HELM_CMD="$HELM_CMD --create-namespace"
    
    # Add values file if specified
    if [[ -n "${VALUES_FILE:-}" ]]; then
        HELM_CMD="$HELM_CMD --values $VALUES_FILE"
    fi
    
    # Add dry-run if specified
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        HELM_CMD="$HELM_CMD --dry-run"
    fi
    
    # Add debug if specified
    if [[ "${DEBUG:-false}" == "true" ]]; then
        HELM_CMD="$HELM_CMD --debug"
    fi
    
    log_info "Executing: $HELM_CMD"
    eval $HELM_CMD
    
    if [[ "${DRY_RUN:-false}" != "true" ]]; then
        log_success "Aiex deployed successfully with Helm"
        wait_for_deployment
    fi
}

deploy_with_kubectl() {
    log_info "Deploying Aiex using kubectl..."
    
    create_namespace
    
    # Deploy manifests in order
    local manifests=(
        "rbac.yaml"
        "configmap.yaml"
        "secret.yaml"
        "pvc.yaml"
        "service.yaml"
        "deployment.yaml"
        "hpa.yaml"
        "pdb.yaml"
        "networkpolicy.yaml"
    )
    
    for manifest in "${manifests[@]}"; do
        local file_path="$MANIFESTS_PATH/$manifest"
        
        if [[ -f "$file_path" ]]; then
            log_info "Applying $manifest..."
            
            if [[ "${DRY_RUN:-false}" == "true" ]]; then
                kubectl apply -f "$file_path" --dry-run=client
            else
                kubectl apply -f "$file_path"
            fi
        else
            log_warning "Manifest file not found: $file_path"
        fi
    done
    
    if [[ "${DRY_RUN:-false}" != "true" ]]; then
        log_success "Aiex deployed successfully with kubectl"
        wait_for_deployment
    fi
}

delete_deployment() {
    log_info "Deleting Aiex deployment..."
    
    # Try Helm first
    if command -v helm &> /dev/null && helm list -n "$NAMESPACE" | grep -q "$RELEASE_NAME"; then
        log_info "Deleting Helm release: $RELEASE_NAME"
        helm uninstall "$RELEASE_NAME" --namespace "$NAMESPACE"
    else
        # Fallback to kubectl
        log_info "Deleting resources with kubectl..."
        if kubectl get namespace "$NAMESPACE" &> /dev/null; then
            kubectl delete all,pvc,secret,configmap,networkpolicy,pdb,hpa -n "$NAMESPACE" --all
        fi
    fi
    
    # Optionally delete namespace
    read -p "Delete namespace $NAMESPACE? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        kubectl delete namespace "$NAMESPACE"
        log_success "Namespace $NAMESPACE deleted"
    fi
    
    log_success "Aiex deployment deleted"
}

wait_for_deployment() {
    log_info "Waiting for deployment to be ready..."
    
    # Wait for deployment to be available
    if kubectl wait --for=condition=available deployment/aiex \
        --namespace="$NAMESPACE" --timeout=300s; then
        log_success "Deployment is ready"
        show_status
    else
        log_error "Deployment did not become ready within timeout"
        show_troubleshooting
        exit 1
    fi
}

show_status() {
    log_info "Deployment status:"
    echo ""
    
    # Show deployments
    echo "Deployments:"
    kubectl get deployments -n "$NAMESPACE"
    echo ""
    
    # Show pods
    echo "Pods:"
    kubectl get pods -n "$NAMESPACE"
    echo ""
    
    # Show services
    echo "Services:"
    kubectl get services -n "$NAMESPACE"
    echo ""
    
    # Show HPA if exists
    if kubectl get hpa -n "$NAMESPACE" &> /dev/null; then
        echo "Horizontal Pod Autoscaler:"
        kubectl get hpa -n "$NAMESPACE"
        echo ""
    fi
    
    # Show ingress if exists
    if kubectl get ingress -n "$NAMESPACE" &> /dev/null; then
        echo "Ingress:"
        kubectl get ingress -n "$NAMESPACE"
        echo ""
    fi
}

show_logs() {
    log_info "Showing Aiex application logs..."
    
    # Get the first pod
    local pod=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=aiex -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    
    if [[ -n "$pod" ]]; then
        kubectl logs -n "$NAMESPACE" "$pod" --follow
    else
        log_error "No Aiex pods found"
        exit 1
    fi
}

show_troubleshooting() {
    log_warning "Deployment troubleshooting information:"
    echo ""
    
    # Show pod status
    echo "Pod status:"
    kubectl get pods -n "$NAMESPACE" -o wide
    echo ""
    
    # Show events
    echo "Recent events:"
    kubectl get events -n "$NAMESPACE" --sort-by='.lastTimestamp' | tail -10
    echo ""
    
    # Show failed pods logs
    local failed_pods=$(kubectl get pods -n "$NAMESPACE" --field-selector=status.phase=Failed -o jsonpath='{.items[*].metadata.name}')
    if [[ -n "$failed_pods" ]]; then
        echo "Failed pod logs:"
        for pod in $failed_pods; do
            echo "--- $pod ---"
            kubectl logs -n "$NAMESPACE" "$pod"
        done
    fi
}

# Parse command line arguments
DRY_RUN="false"
DEBUG="false"
VALUES_FILE=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -n|--namespace)
            NAMESPACE="$2"
            shift 2
            ;;
        -r|--release)
            RELEASE_NAME="$2"
            shift 2
            ;;
        -f|--values-file)
            VALUES_FILE="$2"
            shift 2
            ;;
        -d|--dry-run)
            DRY_RUN="true"
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
        helm|kubectl|delete|status|logs)
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

# Change to script directory
cd "$(dirname "$0")"

# Execute command
case "$COMMAND" in
    helm)
        check_prerequisites
        deploy_with_helm
        ;;
    kubectl)
        check_prerequisites
        deploy_with_kubectl
        ;;
    delete)
        check_prerequisites
        delete_deployment
        ;;
    status)
        check_prerequisites
        show_status
        ;;
    logs)
        check_prerequisites
        show_logs
        ;;
    *)
        log_error "Unknown command: $COMMAND"
        usage
        exit 1
        ;;
esac