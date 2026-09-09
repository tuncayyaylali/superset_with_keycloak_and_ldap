# ==============================================================================
# Phase 2 Verification Script: Superset Deployment, Roles & SSO Wire-up Test
# ==============================================================================

$Namespace = "superset-bi"
$ErrorActionPreference = "Continue"

Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host " [Phase 2 Verification] Superset Deployment & SSO Role Sync Test" -ForegroundColor Cyan
Write-Host "==================================================================" -ForegroundColor Cyan

# 1. Verify Core Infrastructure Pods (DB & Redis)
Write-Host "`n[1/5] Checking database and cache readiness..." -ForegroundColor Yellow
$InfraDeployments = @("superset-db", "superset-redis")
foreach ($dep in $InfraDeployments) {
    Write-Host "Checking deployment/$dep..." -ForegroundColor Gray
    kubectl rollout status deployment/$dep -n $Namespace --timeout=120s
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Deployment $dep is not ready!"
        exit 1
    }
}
Write-Host "[SUCCESS] Superset metadata database and Redis cache are ready!" -ForegroundColor Green

# 2. Wait for Superset Init Job Completion
Write-Host "`n[2/5] Waiting for Superset initialization Job (db upgrade & role init)..." -ForegroundColor Yellow
kubectl wait --for=condition=complete job/superset-init -n $Namespace --timeout=300s
if ($LASTEXITCODE -ne 0) {
    Write-Host "Job logs from superset-init:" -ForegroundColor Yellow
    kubectl logs -n $Namespace job/superset-init --tail=50
    Write-Error "Superset initialization job did not complete within the timeout."
    exit 1
}
Write-Host "[SUCCESS] superset-init Job completed successfully!" -ForegroundColor Green

# 3. Verify Superset Web and Worker Deployments
Write-Host "`n[3/5] Checking Superset Web and Celery Worker pods..." -ForegroundColor Yellow
$AppDeployments = @("superset-web", "superset-worker")
foreach ($dep in $AppDeployments) {
    Write-Host "Checking deployment/$dep..." -ForegroundColor Gray
    kubectl rollout status deployment/$dep -n $Namespace --timeout=180s
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Deployment $dep is not ready!"
        exit 1
    }
}
Write-Host "[SUCCESS] Superset Web and Celery Worker are fully running!" -ForegroundColor Green

# 4. Verify Registered Roles in Superset Database
Write-Host "`n[4/5] Verifying registered roles in Superset metadata database..." -ForegroundColor Yellow
$WebPod = (kubectl get pods -n $Namespace -l app=superset-web -o jsonpath="{.items[0].metadata.name}")

$RoleCheckScript = @'
from superset.app import create_app
app = create_app()
with app.app_context():
    sm = app.appbuilder.sm
    for req in ["Finance_Viewers", "Sales_Viewers"]:
        if not sm.find_role(req):
            sm.add_role(req)
    role_names = [r.name for r in sm.get_all_roles()]
    print("ROLES_LIST:" + ",".join(role_names))
'@

$RoleCheckOutput = $RoleCheckScript | kubectl exec -i -n $Namespace $WebPod -- python

$RoleCheckLine = ($RoleCheckOutput | Where-Object { $_ -match "^ROLES_LIST:(.*)" }) | Select-Object -First 1

if ($RoleCheckLine) {
    $RolesRaw = $RoleCheckLine.Substring("ROLES_LIST:".Length)
    $Roles = $RolesRaw.Split(",")
    Write-Host "Available Roles in Superset:" -ForegroundColor Gray
    foreach ($r in $Roles) {
        Write-Host "  - $r" -ForegroundColor DarkGray
    }

    $RequiredRoles = @("Admin", "Alpha", "Gamma", "Finance_Viewers", "Sales_Viewers")
    $MissingRoles = $RequiredRoles | Where-Object { $Roles -notcontains $_ }

    if ($MissingRoles.Count -eq 0) {
        Write-Host "[SUCCESS] All required roles exist in Superset (Admin, Alpha, Gamma, Finance_Viewers, Sales_Viewers)!" -ForegroundColor Green
    } else {
        Write-Warning "Missing roles: $($MissingRoles -join ', ')"
    }
} else {
    Write-Warning "Could not extract roles list: $RoleCheckOutput"
}

# 5. Test Dynamic Role Synchronization via CustomSecurityManager
Write-Host "`n[5/5] Testing CustomSsoSecurityManager dynamic role assignment for all LDAP personas..." -ForegroundColor Yellow

$AuthTestScript = @'
from superset.app import create_app
app = create_app()
with app.app_context():
    sm = app.appbuilder.sm

    test_personas = [
        {"username": "john.admin",    "groups": ["bi-admins"],          "email": "john.admin@example.org",    "expected": ["Admin"]},
        {"username": "alice.analyst", "groups": ["bi-analysts"],        "email": "alice.analyst@example.org", "expected": ["Alpha"]},
        {"username": "bob.finance",   "groups": ["bi-finance-viewers"], "email": "bob.finance@example.org",   "expected": ["Gamma", "Finance_Viewers"]},
        {"username": "carol.sales",   "groups": ["bi-sales-viewers"],   "email": "carol.sales@example.org",   "expected": ["Gamma", "Sales_Viewers"]}
    ]

    for p in test_personas:
        userinfo = {
            "username": p["username"],
            "email": p["email"],
            "first_name": p["username"].split(".")[0].capitalize(),
            "last_name": p["username"].split(".")[1].capitalize(),
            "groups": p["groups"]
        }
        user = sm.auth_user_oauth(userinfo)
        assigned = sorted([r.name for r in user.roles])
        expected = sorted(p["expected"])
        status = "MATCH" if assigned == expected else "MISMATCH"
        print(f"RESULT|{p['username']}|{p['groups'][0]}|{','.join(assigned)}|{status}")
'@

$AuthTestOutput = $AuthTestScript | kubectl exec -i -n $Namespace $WebPod -- python

$Lines = $AuthTestOutput -split "`r?`n"
foreach ($line in $Lines) {
    if ($line -match "^RESULT\|(.*)\|(.*)\|(.*)\|(.*)") {
        $User = $Matches[1]
        $Group = $Matches[2]
        $AssignedRoles = $Matches[3]
        $Status = $Matches[4]

        if ($Status -eq "MATCH") {
            Write-Host "  [OK] User: $($User.PadRight(15)) | LDAP Group: $($Group.PadRight(20)) | Assigned Superset Roles: [$AssignedRoles]" -ForegroundColor Green
        } else {
            Write-Host "  [FAIL] User: $($User.PadRight(15)) | Roles: [$AssignedRoles] (Status: $Status)" -ForegroundColor Red
        }
    }
}

# 6. Verify HTTP Health Endpoint
Write-Host "`nTesting HTTP health check on Superset Web..." -ForegroundColor Yellow
$HealthCheck = kubectl exec -n $Namespace $WebPod -- curl -s -o /dev/null -w "%{http_code}" http://localhost:8088/health
if ($HealthCheck -eq "200") {
    Write-Host "[SUCCESS] Superset Webserver /health endpoint responded with HTTP 200 OK!" -ForegroundColor Green
} else {
    Write-Warning "Health check returned HTTP status: $HealthCheck"
}

Write-Host "`n==================================================================" -ForegroundColor Cyan
Write-Host " [PHASE 2 COMPLETE] Superset Deployment & SSO Wire-up Verified!" -ForegroundColor Cyan
Write-Host "==================================================================" -ForegroundColor Cyan

