# ==============================================================================
# Teardown Script: Clean removal of all BI Platform Kubernetes Resources
# ==============================================================================

param(
    [switch]$DeletePvc = $false,
    [switch]$DeleteNamespace = $false
)

$Namespace = "superset-bi"
$ErrorActionPreference = "Continue"

Write-Host "==================================================================" -ForegroundColor Yellow
Write-Host "         [TEARDOWN] BI Platform Resource Removal                  " -ForegroundColor Yellow
Write-Host "==================================================================" -ForegroundColor Yellow

if ($DeleteNamespace) {
    Write-Host "Deleting entire namespace '$Namespace' and all enclosed resources..." -ForegroundColor Red
    kubectl delete namespace $Namespace --timeout=120s
    Write-Host "[OK] Namespace '$Namespace' deleted." -ForegroundColor Green
    exit 0
}

Write-Host "Deleting workloads, jobs, and ingress in namespace '$Namespace'..." -ForegroundColor Yellow
kubectl delete -k "$PSScriptRoot\..\deploy\k8s" --ignore-not-found=true

if ($DeletePvc) {
    Write-Host "Deleting persistent volume claims (PVCs)..." -ForegroundColor Red
    kubectl delete pvc --all -n $Namespace
} else {
    Write-Host "Preserving Persistent Volume Claims (PVCs). Use -DeletePvc to remove them." -ForegroundColor Cyan
}

Write-Host "[OK] BI Platform resources removed." -ForegroundColor Green

