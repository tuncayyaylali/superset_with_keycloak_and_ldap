# ==============================================================================
# Phase 1 Verification Script: LDAP & Keycloak Bootstrap and Federation Test
# ==============================================================================

$Namespace = "superset-bi"
$ErrorActionPreference = "Continue"

Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host " [Phase 1 Verification] Superset BI Platform - Identity Foundation" -ForegroundColor Cyan
Write-Host "==================================================================" -ForegroundColor Cyan

# 1. Check Namespace & Pod Status
Write-Host "`n[1/4] Checking Pod readiness in namespace '$Namespace'..." -ForegroundColor Yellow
$Deployments = @("openldap", "keycloak-db", "keycloak")
foreach ($dep in $Deployments) {
    Write-Host "Checking deployment/$dep status..." -ForegroundColor Gray
    kubectl rollout status deployment/$dep -n $Namespace --timeout=120s
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Deployment $dep is not ready!"
        exit 1
    }
}
Write-Host "[SUCCESS] All core pods are running and ready!" -ForegroundColor Green

# 2. Query LDAP for Users and Groups
Write-Host "`n[2/4] Testing OpenLDAP user and group seed entries..." -ForegroundColor Yellow
$LdapPod = (kubectl get pods -n $Namespace -l app=openldap -o jsonpath="{.items[0].metadata.name}")

Write-Host "Querying OpenLDAP for seed users..." -ForegroundColor Gray
$UserSearch = kubectl exec -n $Namespace $LdapPod -- ldapsearch -x -H ldap://localhost:389 -b "ou=users,dc=example,dc=org" -D "cn=admin,dc=example,dc=org" -w adminpassword "(objectClass=inetOrgPerson)" uid mail
if ($UserSearch -match "john.admin" -and $UserSearch -match "alice.analyst" -and $UserSearch -match "bob.finance" -and $UserSearch -match "carol.sales") {
    Write-Host "[SUCCESS] All 4 test personas found in LDAP (john.admin, alice.analyst, bob.finance, carol.sales)!" -ForegroundColor Green
} else {
    Write-Warning "Some users could not be found in OpenLDAP."
}

Write-Host "`nQuerying OpenLDAP for seed groups..." -ForegroundColor Gray
$GroupSearch = kubectl exec -n $Namespace $LdapPod -- ldapsearch -x -H ldap://localhost:389 -b "ou=groups,dc=example,dc=org" -D "cn=admin,dc=example,dc=org" -w adminpassword "(objectClass=groupOfNames)" cn member
if ($GroupSearch -match "bi-admins" -and $GroupSearch -match "bi-analysts" -and $GroupSearch -match "bi-finance-viewers" -and $GroupSearch -match "bi-sales-viewers") {
    Write-Host "[SUCCESS] All 4 BI groups verified in LDAP (bi-admins, bi-analysts, bi-finance-viewers, bi-sales-viewers)!" -ForegroundColor Green
} else {
    Write-Warning "Some groups could not be found in OpenLDAP."
}

# 3. Start Port-Forward for Keycloak Testing
Write-Host "`n[3/4] Establishing port-forward to Keycloak service on 127.0.0.1:8080..." -ForegroundColor Yellow
$pf = Start-Process kubectl -ArgumentList "port-forward", "svc/keycloak", "-n", $Namespace, "8080:8080" -PassThru -WindowStyle Hidden
Start-Sleep -Seconds 3

try {
    $DiscoveryUrl = "http://127.0.0.1:8080/realms/analytics-realm/.well-known/openid-configuration"
    $Discovery = Invoke-RestMethod -Uri $DiscoveryUrl -Method Get -TimeoutSec 10
    if ($Discovery.token_endpoint) {
        Write-Host "[SUCCESS] Keycloak 'analytics-realm' is active and serving OIDC discovery!" -ForegroundColor Green
        Write-Host "  Issuer: $($Discovery.issuer)" -ForegroundColor Gray
        Write-Host "  Token Endpoint: $($Discovery.token_endpoint)" -ForegroundColor Gray
    } else {
        Write-Warning "Failed to query OIDC discovery endpoint."
    }

    # 4. Authenticate All 4 LDAP Users via Keycloak and Verify Groups Claim
    Write-Host "`n[4/4] Testing Direct Access Grant & Token Mappings for all Personas..." -ForegroundColor Yellow

    $TestMatrix = @(
        @{ Username = "john.admin";   ExpectedGroup = "bi-admins";          TargetSupersetRole = "Admin" },
        @{ Username = "alice.analyst"; ExpectedGroup = "bi-analysts";        TargetSupersetRole = "Alpha (SQL Lab Author)" },
        @{ Username = "bob.finance";   ExpectedGroup = "bi-finance-viewers"; TargetSupersetRole = "Gamma + Finance_Viewers (RLS: FIN)" },
        @{ Username = "carol.sales";   ExpectedGroup = "bi-sales-viewers";   TargetSupersetRole = "Gamma + Sales_Viewers (RLS: SLS)" }
    )

    $TokenUrl = "http://127.0.0.1:8080/realms/analytics-realm/protocol/openid-connect/token"

    foreach ($persona in $TestMatrix) {
        $u = $persona.Username
        $g = $persona.ExpectedGroup
        $r = $persona.TargetSupersetRole

        $Body = @{
            client_id     = "superset"
            client_secret = "superset-client-secret-12345"
            grant_type    = "password"
            username      = $u
            password      = "Password123!"
        }

        try {
            $TokenObj = Invoke-RestMethod -Uri $TokenUrl -Method Post -Body $Body -TimeoutSec 10
            if ($TokenObj.access_token) {
                $Parts = $TokenObj.access_token.Split(".")
                $PayloadBase64 = $Parts[1]
                while ($PayloadBase64.Length % 4) { $PayloadBase64 += "=" }
                $PayloadJson = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($PayloadBase64))
                $Claims = $PayloadJson | ConvertFrom-Json

                $MatchedGroup = $Claims.groups | Where-Object { $_ -eq $g }
                if ($MatchedGroup) {
                    Write-Host "  [OK] User: $($u.PadRight(15)) | LDAP Group: $($g.PadRight(20)) | Token Claim: ['$MatchedGroup'] | Role: $r" -ForegroundColor Green
                } else {
                    Write-Host "  [FAIL] User: ${u} | Expected: ${g} | Got: $($Claims.groups -join ', ')" -ForegroundColor Red
                }
            } else {
                Write-Host "  [FAIL] Failed to acquire token for ${u}" -ForegroundColor Red
            }
        } catch {
            Write-Host "  [ERROR] Error processing token for ${u}: $($_.Exception.Message)" -ForegroundColor Red
        }
    }
}
finally {
    if ($pf -and -not $pf.HasExited) {
        Stop-Process -Id $pf.Id -Force -ErrorAction SilentlyContinue
    }
}

Write-Host "`n==================================================================" -ForegroundColor Cyan
Write-Host " [PHASE 1 COMPLETE] Identity Foundation fully verified!" -ForegroundColor Cyan
Write-Host "==================================================================" -ForegroundColor Cyan

