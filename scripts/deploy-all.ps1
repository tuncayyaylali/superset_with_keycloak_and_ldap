# ==============================================================================
# Master Deployment Automation: Full Enterprise BI Platform
# Deploys LDAP, Keycloak, PostgreSQL, Redis, and Apache Superset with RLS & SSO
# ==============================================================================

$Namespace = "superset-bi"
$ErrorActionPreference = "Stop"

Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host "     [MASTER DEPLOY] Superset + Keycloak + OpenLDAP Enterprise    " -ForegroundColor Cyan
Write-Host "==================================================================" -ForegroundColor Cyan

# 1. Cluster connectivity pre-flight check
Write-Host "`n[1/6] Verifying Kubernetes cluster connectivity..." -ForegroundColor Yellow
$ClusterInfo = kubectl cluster-info
if ($LASTEXITCODE -ne 0) {
    Write-Error "Cannot connect to Kubernetes cluster. Please ensure your kubeconfig is active."
    exit 1
}
Write-Host "[OK] Connected to Kubernetes cluster." -ForegroundColor Green

# 2. Apply Master Kustomization
Write-Host "`n[2/6] Applying all Kubernetes manifests via Kustomize..." -ForegroundColor Yellow
kubectl apply -k "$PSScriptRoot\..\deploy\k8s"
Write-Host "[OK] Kubernetes manifests applied." -ForegroundColor Green

# 3. Wait for Identity & Directory Services (Phase 1)
Write-Host "`n[3/6] Waiting for OpenLDAP and Keycloak to become ready..." -ForegroundColor Yellow
kubectl wait --for=condition=ready pod -l app=openldap -n $Namespace --timeout=180s
kubectl wait --for=condition=ready pod -l app=keycloak-db -n $Namespace --timeout=180s
kubectl rollout status deployment/keycloak -n $Namespace --timeout=300s
kubectl rollout status deployment/phpldapadmin -n $Namespace --timeout=180s
Write-Host "[OK] Identity & Directory services (LDAP, Keycloak, phpLDAPadmin) are healthy." -ForegroundColor Green

# 4. Wait for Superset Infrastructure (Phase 2)
Write-Host "`n[4/6] Waiting for Superset Database, Redis, and Web Services..." -ForegroundColor Yellow
kubectl wait --for=condition=ready pod -l app=superset-db -n $Namespace --timeout=180s
kubectl wait --for=condition=ready pod -l app=superset-redis -n $Namespace --timeout=180s

# Seed Analytics Data Warehouse in PostgreSQL
Write-Host "Ensuring analytics_dw database and schema exist in PostgreSQL..." -ForegroundColor Yellow
$DbPod = (kubectl get pods -n $Namespace -l app=superset-db -o jsonpath="{.items[0].metadata.name}")
kubectl exec -n $Namespace $DbPod -- psql -U superset -d postgres -c "SELECT 1 FROM pg_database WHERE datname = 'analytics_dw'" | Out-Null
kubectl exec -n $Namespace $DbPod -- psql -U superset -d postgres -tc "SELECT 1 FROM pg_database WHERE datname = 'analytics_dw'" | ForEach-Object {
    if ($_ -notmatch "1") {
        Write-Host "Creating analytics_dw database..." -ForegroundColor Yellow
        kubectl exec -n $Namespace $DbPod -- psql -U superset -d postgres -c "CREATE DATABASE analytics_dw;"
    }
}
Get-Content "$PSScriptRoot\..\data\schema.sql" | kubectl exec -i -n $Namespace $DbPod -- psql -U superset -d analytics_dw
Write-Host "[OK] Analytics Data Warehouse (fact_orders) populated." -ForegroundColor Green

# Wait for Superset Web and Worker
kubectl rollout status deployment/superset-web -n $Namespace --timeout=300s
kubectl rollout status deployment/superset-worker -n $Namespace --timeout=300s
Write-Host "[OK] Superset web and worker pods are ready." -ForegroundColor Green

# 5. Configure Governance, RLS, and Populate Dashboards (Phase 3)
Write-Host "`n[5/6] Configuring Data Governance, Row-Level Security & Dashboards..." -ForegroundColor Yellow
Get-Content "$PSScriptRoot\configure-superset-governance.py" | kubectl exec -i -n $Namespace deployment/superset-web -- python
Get-Content "$PSScriptRoot\populate-dashboards.py" | kubectl exec -i -n $Namespace deployment/superset-web -- python
Write-Host "[OK] Governance policies, RLS rules, and dashboard charts configured." -ForegroundColor Green

# 6. Deployment Complete & Instructions
Write-Host "`n==================================================================" -ForegroundColor Cyan
Write-Host "               DEPLOYMENT SUCCESSFULLY COMPLETED!                 " -ForegroundColor Cyan
Write-Host "==================================================================" -ForegroundColor Cyan

Write-Host @"
To access the platform locally, run these port-forward commands in separate terminals:

  1. Superset Web:
     kubectl port-forward svc/superset -n $Namespace 8088:8088

  2. Keycloak Admin / SSO:
     kubectl port-forward svc/keycloak -n $Namespace 8080:8080

  3. phpLDAPadmin Web GUI:
     kubectl port-forward svc/phpldapadmin -n $Namespace 8085:80

Access URLs:
  - Apache Superset: http://localhost:8088
  - Keycloak Realm:  http://localhost:8080/admin (User: admin / Password: adminpassword)
  - phpLDAPadmin:    http://localhost:8085 (Login DN: cn=admin,dc=example,dc=org / Password: adminpassword)

Test User Logins (Password for all: Password123!):
  - john.admin   -> Role: Admin (Full platform access, SQL Lab, all data)
  - alice.analyst -> Role: Alpha (SQL Lab access, dataset creation)
  - bob.finance  -> Role: Gamma + Finance_Viewers (Finance dashboard, RLS: department_code = 'FIN')
  - carol.sales  -> Role: Gamma + Sales_Viewers (Sales dashboard, RLS: department_code = 'SLS')
"@ -ForegroundColor Green

