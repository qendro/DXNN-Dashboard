#!/bin/bash
# Resolve Docker-host paths from this checkout, even when invoked elsewhere.
set -euo pipefail
dashboard_root="$(cd "$(dirname "$0")" && pwd -P)"
deployment_root="$(cd "$dashboard_root/../AWS-Deployment" && pwd -P)"
export HOST_AWS_DEPLOYMENT_PATH="${HOST_AWS_DEPLOYMENT_PATH:-$deployment_root}"
export HOST_OCI_ADAPTER_PATH="${HOST_OCI_ADAPTER_PATH:-$dashboard_root/scripts/oci_dashboard.py}"
cd "$dashboard_root"
exec docker compose "$@"
