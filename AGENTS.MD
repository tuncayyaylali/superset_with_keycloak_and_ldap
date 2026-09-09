# AGENTS.md

## Project Vision & Context
Build an enterprise-grade Business Intelligence platform on Kubernetes leveraging **Apache Superset**, **PostgreSQL**, **Keycloak**, and **LDAP (OpenLDAP / Active Directory)**.
Identity lifecycle and group memberships are fully mastered in LDAP, federated via Keycloak (OIDC), and propagated into Superset. Access control is enforced at both the dashboard level (RBAC) and the row level (Row Level Security - RLS).

---

## Autonomous Agent Team Roles

### 1. Infrastructure & Kubernetes Agent (`infra-agent`)
* **Primary Scope:** Deployments, Services, Ingress, Secrets, and Helm orchestration.
* **Responsibilities:**
  * Configure Kubernetes manifests and Helm charts for:
    * OpenLDAP (with preloaded schemas and initial seed LDIF).
    * Keycloak (HA or standalone stateful set backed by PostgreSQL).
    * PostgreSQL (separate DBs/schemas for Superset metadata, Keycloak storage, and business analytics data).
    * Apache Superset (Webserver, Celery workers, Celery beat, and Redis broker).
  * Enforce mutual network policies, TLS termination via Ingress Controller (e.g., Traefik/Nginx), and sensitive credentials injection via Kubernetes Secrets.
* **Deliverables:**
  * `deploy/k8s/` or `deploy/helm/` templates.
  * Environment variable schemas (`.env.example`) and Secret specs.

### 2. IAM & Directory Services Agent (`iam-agent`)
* **Primary Scope:** LDAP directory topology and Keycloak federation.
* **Responsibilities:**
  * Define the LDAP Organizational Units (OUs):
    * `ou=users,dc=example,dc=org`
    * `ou=groups,dc=example,dc=org` (e.g., `bi-admins`, `bi-analysts`, `bi-finance-viewers`, `bi-sales-viewers`).
  * Configure Keycloak:
    * Realm definition (e.g., `analytics-realm`).
    * LDAP User Federation provider with periodic or on-demand sync.
    * `group-ldap-mapper` configuration to inject user groups into OIDC tokens.
    * OIDC Confidential Client for Superset (`client_id: superset`) with redirect URIs:
      `https://<superset-host>/oauth-authorized/keycloak`.
* **Deliverables:**
  * `iam/ldap/bootstrap.ldif`: Initial seed tree with test users and group assignments.
  * `iam/keycloak/realm-export.json`: Keycloak realm configuration ready for automated import.

### 3. Superset Security & Integration Agent (`superset-agent`)
* **Primary Scope:** Superset configuration, custom auth manager, and RBAC mapping.
* **Responsibilities:**
  * Implement `CustomSecurityManager` extending `SupersetSecurityManager` inside `superset_config.py`.
  * Decode Keycloak JWT claims (`groups` array) to map users to Superset roles dynamically on login:
    * `bi-admins` -> `Admin`
    * `bi-analysts` -> `Alpha` (SQL Lab access, dataset creation)
    * `bi-*-viewers` -> `Gamma` + custom team roles (No SQL Lab, restricted views)
  * Enable critical feature flags in `superset_config.py`:
    ```python
    FEATURE_FLAGS = {
        "DASHBOARD_RBAC": True,
        "ENABLE_TEMPLATE_PROCESSING": True
    }
    ```
  * Setup headless initialization scripts (`superset fab create-admin`, `superset db upgrade`, `superset init`).
* **Deliverables:**
  * `superset/config/superset_config.py`
  * `superset/security/custom_sso_security_manager.py`
  * `superset/docker/Dockerfile` (if building custom image with dependencies like `pyjwt`, `psycopg2-binary`).

### 4. Data Governance & Analytics Agent (`governance-agent`)
* **Primary Scope:** Row-Level Security (RLS) rules and dataset governance in PostgreSQL.
* **Responsibilities:**
  * Construct sample schemas and analytics tables in PostgreSQL with multi-tenant/departmental identifiers (e.g., `department_code`, `region`).
  * Design and document Superset RLS policies linked to dynamic roles:
    * E.g., Table `fact_orders`: Clause `department_code = 'FIN'` mapped to role `Finance_Viewers`.
  * Define Dashboard RBAC policies to restrict visibility so viewers only see dashboards assigned to their explicit role.
* **Deliverables:**
  * `data/schema.sql`: DDL and mock data statements.
  * `docs/rls_matrix.md`: Mapping table defining LDAP Group <-> Superset Role <-> Allowed Dashboards <-> RLS Clause.

---

## Technical Specifications & Architecture

```
             [ User Browser ]
                    |
                    | 1. Login Request
                    v
             [ Superset Web ]  (OIDC / OAuth2)
                    |
                    | 2. Redirect to IDP
                    v
             [ Keycloak IDP ]
                    |
                    | 3. Credential validation & Group lookup
                    v
              [ LDAP Server ]
```

### Component Stack
| Layer | Technology | Primary Task |
| :--- | :--- | :--- |
| **Directory** | OpenLDAP / Active Directory | Master source for user identities & memberships |
| **Auth Broker** | Keycloak | OIDC broker, token issuer with `groups` claim |
| **Presentation & BI** | Apache Superset | Dashboard rendering, FAB Custom Security Manager, RLS |
| **Database** | PostgreSQL | Application metadata store & Analytics warehouse |
| **Orchestration** | Kubernetes | Container runtime, service discovery, config management |

---

## Implementation Phases & Milestones

### Phase 1: Directory & Identity Foundation
1. Deploy LDAP with sample user structure (`ou=users`) and department groups (`ou=groups`).
2. Deploy Keycloak; configure LDAP User Federation and verify sync.
3. Configure Keycloak client `superset` with client secret and custom mapper for `groups`.

### Phase 2: Superset Deployment & SSO Wire-up
1. Deploy PostgreSQL for Superset metadata storage.
2. Build Superset container bundling custom security manager script.
3. Configure `superset_config.py` with `AUTH_OID`, OAuth provider blocks, and `DASHBOARD_RBAC: True`.
4. Validate single sign-on flow: ensure logging in via Keycloak creates the Superset user with correct mapped roles.

### Phase 3: Access Control & Row-Level Security Testing
1. Populate business sample tables in PostgreSQL.
2. Configure Dashboards in Superset and bind them to specific roles (`DASHBOARD_RBAC`).
3. Configure Row Level Security rules under **Settings > Row Level Security**.
4. Run integration tests:
   * **Admin User:** Can access all dashboards, run SQL in SQL Lab, view unmasked full rows.
   * **Analyst User:** Can run SQL Lab queries, see assigned dashboards, affected by RLS.
   * **Finance Viewer User:** Cannot access SQL Lab, sees only Finance dashboard, queries filtered by `department_code = 'FIN'`.

---

## Agent Collaboration Rules
* No hardcoded credentials: All secrets must be managed via `.env` or Kubernetes Secret abstractions.
* Idempotency: All setup scripts (LDAP bootstrap, Keycloak import, Superset role provisioning) must be safe to execute multiple times.
* Security First: Users mapped to `Gamma` role must never be granted permissions containing `can_sqllab` or `can_write`.

