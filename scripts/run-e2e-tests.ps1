# ==============================================================================
# End-to-End Test Suite: Unified Verification for All Three Architectural Phases
# ==============================================================================

$Namespace = "superset-bi"
$ErrorActionPreference = "Continue"

Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host "       [E2E TEST RUNNER] BI PLATFORM FULL COMPLIANCE SUITE        " -ForegroundColor Cyan
Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray

$Results = [ordered]@{}

# ------------------------------------------------------------------------------
# Phase 1: Identity & Federation Verification
# ------------------------------------------------------------------------------
Write-Host "`n>>> [1/3] RUNNING PHASE 1 VERIFICATION (LDAP & Keycloak OIDC) <<<" -ForegroundColor Yellow
$p1_start = Get-Date
& "$PSScriptRoot\verify-phase1.ps1"
if ($LASTEXITCODE -eq 0) {
    $Results["Phase 1: LDAP Directory & Keycloak Federation"] = "PASSED"
} else {
    $Results["Phase 1: LDAP Directory & Keycloak Federation"] = "FAILED"
}

# ------------------------------------------------------------------------------
# Phase 2: Superset SSO & Dynamic Role Mapping Verification
# ------------------------------------------------------------------------------
Write-Host "`n>>> [2/3] RUNNING PHASE 2 VERIFICATION (Superset SSO & Role Mapping) <<<" -ForegroundColor Yellow
$p2_start = Get-Date
& "$PSScriptRoot\verify-phase2.ps1"
if ($LASTEXITCODE -eq 0) {
    $Results["Phase 2: Superset SSO & Dynamic RBAC Engine"] = "PASSED"
} else {
    $Results["Phase 2: Superset SSO & Dynamic RBAC Engine"] = "FAILED"
}

# ------------------------------------------------------------------------------
# Phase 3: Analytics DW, Dashboard RBAC & Row-Level Security Verification
# ------------------------------------------------------------------------------
Write-Host "`n>>> [3/3] RUNNING PHASE 3 VERIFICATION (Governance & RLS Security) <<<" -ForegroundColor Yellow
$p3_start = Get-Date
& "$PSScriptRoot\verify-phase3.ps1"
if ($LASTEXITCODE -eq 0) {
    $Results["Phase 3: Multi-Tenant Data Governance & RLS Filtering"] = "PASSED"
} else {
    $Results["Phase 3: Multi-Tenant Data Governance & RLS Filtering"] = "FAILED"
}

# ------------------------------------------------------------------------------
# Consolidated Summary Report
# ------------------------------------------------------------------------------
Write-Host "`n==================================================================" -ForegroundColor Cyan
Write-Host "                      E2E TEST SCORECARD                          " -ForegroundColor Cyan
Write-Host "==================================================================" -ForegroundColor Cyan

$allPassed = $true
foreach ($test in $Results.Keys) {
    $status = $Results[$test]
    if ($status -eq "PASSED") {
        Write-Host " [PASS] $test" -ForegroundColor Green
    } else {
        Write-Host " [FAIL] $test" -ForegroundColor Red
        $allPassed = $false
    }
}

Write-Host "------------------------------------------------------------------" -ForegroundColor Cyan
if ($allPassed) {
    Write-Host " [ALL TESTS PASSED] Architecture fully compliant with AGENTS.md!" -ForegroundColor Green
    exit 0
} else {
    Write-Host " [WARNING] Some verification checks failed. Review logs above." -ForegroundColor Red
    exit 1
}

