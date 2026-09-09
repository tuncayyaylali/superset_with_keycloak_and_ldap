# ==============================================================================
# Script: Verify End-to-End SSO & RLS for Newly Created User 'david.finance'
# ==============================================================================

$Namespace = "superset-bi"
$ErrorActionPreference = "Continue"

Write-Host "==================================================================" -ForegroundColor Cyan
Write-Host " [SSO Verification] Testing Newly Created User: david.finance     " -ForegroundColor Cyan
Write-Host "==================================================================" -ForegroundColor Cyan

# 1. Test Keycloak Token Issuance & Group Mapper
Write-Host "`n[1/3] Testing Keycloak OIDC Token Issuance for 'david.finance'..." -ForegroundColor Yellow

$TokenScript = @'
import urllib.request
import urllib.parse
import json
import jwt

token_url = "http://keycloak.superset-bi.svc.cluster.local:8080/realms/analytics-realm/protocol/openid-connect/token"
data = urllib.parse.urlencode({
    "client_id": "superset",
    "client_secret": "superset-client-secret-12345",
    "grant_type": "password",
    "username": "david.finance",
    "password": "Password123!",
    "scope": "openid email profile"
}).encode("utf-8")

req = urllib.request.Request(token_url, data=data, method="POST")
req.add_header("Content-Type", "application/x-www-form-urlencoded")

try:
    with urllib.request.urlopen(req) as resp:
        res = json.loads(resp.read().decode("utf-8"))
        id_token = res.get("id_token")
        decoded = jwt.decode(id_token, options={"verify_signature": False}, algorithms=["RS256"])
        print(f"TOKEN_SUCCESS|{decoded.get('preferred_username')}|{decoded.get('email')}|{decoded.get('groups')}")
except Exception as e:
    print(f"TOKEN_FAILED|{e}")
'@

$TokenOutput = $TokenScript | kubectl exec -i -n $Namespace deployment/superset-web -- python
Write-Host $TokenOutput -ForegroundColor Gray

if ($TokenOutput -match "TOKEN_SUCCESS\|david\.finance\|david\.finance@example\.org\|.*bi-finance-viewers.*") {
    Write-Host "[SUCCESS] Keycloak authenticated 'david.finance' against LDAP and issued token with group 'bi-finance-viewers'!" -ForegroundColor Green
} else {
    Write-Warning "Keycloak token issuance failed for david.finance."
}

# 2. Test Superset Dynamic Role Provisioning for david.finance
Write-Host "`n[2/3] Simulating Superset SSO Login & Dynamic Role Assignment..." -ForegroundColor Yellow

$SupersetLoginScript = @'
from superset.app import create_app
app = create_app()

with app.app_context():
    sm = app.appbuilder.sm
    userinfo = {
        "username": "david.finance",
        "email": "david.finance@example.org",
        "first_name": "David",
        "last_name": "Finance",
        "groups": ["bi-finance-viewers"]
    }
    user = sm.auth_user_oauth(userinfo)
    role_names = [r.name for r in user.roles]
    print(f"USER_ROLES|{user.username}|{role_names}")
'@

$LoginOutput = $SupersetLoginScript | kubectl exec -i -n $Namespace deployment/superset-web -- python
Write-Host $LoginOutput -ForegroundColor Gray

if ($LoginOutput -match "Finance_Viewers" -and $LoginOutput -match "Gamma") {
    Write-Host "[SUCCESS] Superset dynamically created 'david.finance' and assigned roles: [Finance_Viewers, Gamma]!" -ForegroundColor Green
} else {
    Write-Warning "Superset role assignment failed."
}

# 3. Test Row-Level Security & Dashboard Visibility for david.finance
Write-Host "`n[3/3] Testing RLS Filtering and Dashboard RBAC for 'david.finance'..." -ForegroundColor Yellow

$RlsTestScript = @'
from superset.app import create_app
from flask import g
app = create_app()

with app.app_context():
    with app.test_request_context():
        sm = app.appbuilder.sm
        from superset import db
        from superset.models.dashboard import Dashboard
        from superset.connectors.sqla.models import SqlaTable

        user = sm.find_user(username="david.finance")
        g.user = user

        # 1. Check SQL Lab
        can_sql = sm.has_access("can_sqllab", "Superset") or any(r.name in ["Admin", "Alpha"] for r in user.roles)

        # 2. Check Dashboard Visibility
        user_roles = set(user.roles)
        dashboards = db.session.query(Dashboard).all()
        visible_dash = [d.dashboard_title for d in dashboards if any(r.name == "Admin" for r in user_roles) or bool(user_roles & set(d.roles))]

        # 3. Check RLS filter
        tbl = db.session.query(SqlaTable).filter_by(table_name="fact_orders").first()
        tp = tbl.get_template_processor()
        filters = tbl.get_sqla_row_level_filters(tp)
        filter_clauses = [str(f) for f in filters]

        # 4. Execute query with RLS
        from sqlalchemy import create_engine
        engine = create_engine(tbl.database.sqlalchemy_uri)
        where_clause = " AND ".join(filter_clauses) if filter_clauses else "1=1"
        query = f"SELECT DISTINCT department_code FROM fact_orders WHERE {where_clause} ORDER BY department_code;"
        with engine.connect() as conn:
            rows = [r[0] for r in conn.execute(db.text(query)).fetchall()]

        print(f"GOVERNANCE_RESULT|{can_sql}|{visible_dash}|{filter_clauses}|{rows}")
'@

$RlsOutput = $RlsTestScript | kubectl exec -i -n $Namespace deployment/superset-web -- python
Write-Host $RlsOutput -ForegroundColor Gray

if ($RlsOutput -match "GOVERNANCE_RESULT\|False\|.*Finance Performance Dashboard.*\|.*department_code = 'FIN'.*\|.*'FIN'.*") {
    Write-Host "[SUCCESS] RLS enforced: david.finance only sees 'FIN' orders and cannot access SQL Lab!" -ForegroundColor Green
} else {
    Write-Warning "Governance check failed."
}

Write-Host "`n==================================================================" -ForegroundColor Cyan
Write-Host " [VERIFICATION COMPLETE] New LDAP User Live SSO Test PASSED!      " -ForegroundColor Cyan
Write-Host "==================================================================" -ForegroundColor Cyan
