# Enterprise BI Platform: Apache Superset with Keycloak and OpenLDAP

An enterprise-grade Business Intelligence platform deployed on Kubernetes, integrating **Apache Superset**, **Keycloak**, **OpenLDAP**, and **PostgreSQL**.

User identities and departmental memberships are mastered inside OpenLDAP, federated to Keycloak via OpenID Connect (OIDC), and synchronized dynamically into Apache Superset upon login. Access control is strictly enforced at both the dashboard level (Dashboard RBAC) and the database query layer (Row-Level Security / RLS).

This repository contains all production Kubernetes manifests, LDAP seed structures, Keycloak realm definitions, and database schemas. Deployments are executed via standard `kubectl` CLI commands, while administration, user management, and governance configurations are performed directly through their respective Web UIs.

---

## Architecture Diagram

```mermaid
flowchart TD
    User([End-User Browser]) -->|1. Access http://localhost:8088| Ingress[Kubernetes Ingress / Service Proxy]
    Ingress -->|Route /| SupersetWeb[Apache Superset Webserver]
    Ingress -->|Route /auth| Keycloak[Keycloak OIDC Broker]
    Ingress -->|Route /ldap| PhpLdapAdmin[phpLDAPadmin Web UI]

    SupersetWeb -->|2. Redirect for Single Sign-On| Keycloak
    Keycloak -->|3. Bind and Validate Credentials| OpenLDAP[(OpenLDAP Directory\ndc=example,dc=org)]
    Keycloak -->|4. Issue Signed OIDC Token with groups claim| SupersetWeb

    SupersetWeb -->|5. Dynamic Role Mapping| CustomSM[CustomSsoSecurityManager]
    CustomSM -->|Store User and Role Mappings| SupersetDB[(PostgreSQL\nsuperset metadata)]

    SupersetWeb -->|6. Query Fact Data with RLS Filtering| AnalyticsDW[(PostgreSQL\nanalytics_dw)]
    SupersetWeb -->|Async Queries and Caching| Redis[(Redis Broker and Cache)]
    Worker[Superset Celery Worker] --> Redis
    Worker --> AnalyticsDW
```

---

## Component Stack

* **Directory Service**: OpenLDAP (`osixia/openldap:1.5.0`) with standard schemas (`ou=users`, `ou=groups`).
* **Directory Administration**: phpLDAPadmin (`osixia/phpldapadmin:0.9.0`) for web-based directory management.
* **Identity and Access Management (IAM)**: Keycloak 24.0.5 running on Quarkus with PostgreSQL storage.
* **Business Intelligence (BI)**: Apache Superset 3.1.1 with Celery worker and Redis broker.
* **Databases**: PostgreSQL 15 hosting both Superset application metadata (`superset`) and business analytics data warehouse (`analytics_dw`).
* **Security & Network Isolation**: Kubernetes manifests managed via Kustomize, reinforced by zero-trust Kubernetes NetworkPolicies.

---

## Role and Access Control Matrix

The default password for all seed LDAP users is: `Password123!`

| User Name | LDAP Group | Mapped Superset Roles | Dashboard Visibility | Row-Level Security (RLS) Filter | SQL Lab Access |
| :--- | :--- | :--- | :--- | :--- | :---: |
| `john.admin` | `bi-admins` | `Admin` | All Dashboards (Executive, Finance, Sales) | None (Full 11 orders visible across all departments) | Granted |
| `alice.analyst` | `bi-analysts` | `Alpha` | Executive Enterprise Overview | None (Full raw orders visible for analytical querying) | Granted |
| `bob.finance` | `bi-finance-viewers` | `Gamma`, `Finance_Viewers` | Finance Performance Dashboard only | `department_code = 'FIN'` (Only 4 Finance orders visible) | Denied |
| `carol.sales` | `bi-sales-viewers` | `Gamma`, `Sales_Viewers` | Sales Revenue Dashboard only | `department_code = 'SLS'` (Only 4 Sales orders visible) | Denied |

> [!IMPORTANT]
> **Least Privilege Enforcement**: Users mapped to `Gamma` viewer roles (`Finance_Viewers`, `Sales_Viewers`) are strictly barred from SQL Lab (`can_sqllab`), edit permissions (`can_write`), and administrative panels by `CustomSsoSecurityManager`.

---

## Prerequisites

Before deploying the platform, ensure the following tools are installed:

* Kubernetes cluster (Docker Desktop Kubernetes, Minikube, or Kind).
* `kubectl` CLI configured with cluster-admin access.

---

## Part 1: Platform Deployment via kubectl

All Kubernetes resources are structured in the `deploy/k8s/` directory and can be deployed step-by-step or in a single command.

### Option A: Step-by-Step Deployment

#### 1. Create Namespace and Secrets
Initialize the dedicated namespace and load infrastructure secrets:

```bash
kubectl apply -f deploy/k8s/namespace.yaml
kubectl apply -f deploy/k8s/secrets.yaml
```

#### 2. Deploy OpenLDAP and phpLDAPadmin (Phase 1)
Deploy the directory service, bootstrap schemas, and web administration interface:

```bash
kubectl apply -f deploy/k8s/ldap/configmap.yaml
kubectl apply -f deploy/k8s/ldap/pvc.yaml
kubectl apply -f deploy/k8s/ldap/deployment.yaml
kubectl apply -f deploy/k8s/ldap/service.yaml
kubectl apply -f deploy/k8s/ldap/phpldapadmin.yaml

# Wait for LDAP services to become ready
kubectl wait --for=condition=ready pod -l app=openldap -n superset-bi --timeout=180s
kubectl rollout status deployment/phpldapadmin -n superset-bi --timeout=180s
```

#### 3. Deploy Keycloak Identity Broker (Phase 1)
Deploy PostgreSQL storage for Keycloak, configure the automated realm import, and start Keycloak:

```bash
kubectl apply -f deploy/k8s/keycloak/postgres-pvc.yaml
kubectl apply -f deploy/k8s/keycloak/postgres-deployment.yaml
kubectl apply -f deploy/k8s/keycloak/postgres-service.yaml
kubectl apply -f deploy/k8s/keycloak/realm-configmap.yaml
kubectl apply -f deploy/k8s/keycloak/deployment.yaml
kubectl apply -f deploy/k8s/keycloak/service.yaml

# Wait for Keycloak to become ready
kubectl wait --for=condition=ready pod -l app=keycloak-db -n superset-bi --timeout=180s
kubectl rollout status deployment/keycloak -n superset-bi --timeout=300s
```

#### 4. Deploy Apache Superset Infrastructure (Phase 2)
Deploy PostgreSQL metadata DB, Redis cache, Superset configuration files, run the initialization Job, and start the Webserver and Worker:

```bash
kubectl apply -f deploy/k8s/superset/db-pvc.yaml
kubectl apply -f deploy/k8s/superset/db-deployment.yaml
kubectl apply -f deploy/k8s/superset/db-service.yaml
kubectl apply -f deploy/k8s/superset/redis-deployment.yaml
kubectl apply -f deploy/k8s/superset/redis-service.yaml
kubectl apply -f deploy/k8s/superset/configmap.yaml
kubectl apply -f deploy/k8s/superset/service.yaml

# Wait for Superset database and Redis
kubectl wait --for=condition=ready pod -l app=superset-db -n superset-bi --timeout=180s
kubectl wait --for=condition=ready pod -l app=superset-redis -n superset-bi --timeout=180s

# Run database migrations and role initialization
kubectl apply -f deploy/k8s/superset/init-job.yaml
kubectl wait --for=condition=complete job/superset-init -n superset-bi --timeout=300s

# Deploy Superset Web and Celery Worker
kubectl apply -f deploy/k8s/superset/web-deployment.yaml
kubectl apply -f deploy/k8s/superset/worker-deployment.yaml
kubectl rollout status deployment/superset-web -n superset-bi --timeout=300s
kubectl rollout status deployment/superset-worker -n superset-bi --timeout=300s
```

#### 5. Apply Ingress and Zero-Trust Network Policies (Phase 4)
Configure HTTP routing and enforce zero-trust inter-pod network isolation:

```bash
kubectl apply -f deploy/k8s/ingress.yaml
kubectl apply -f deploy/k8s/network-policies.yaml
```

---

### Option B: Single-Command Deployment via Kustomize

Alternatively, deploy all manifests simultaneously:

```bash
kubectl apply -k deploy/k8s
```

Wait for all pods in the `superset-bi` namespace to reach Running / Completed status:

```bash
kubectl get pods -n superset-bi -w
```

---

## Part 2: Seeding the Business Analytics Data Warehouse

The PostgreSQL container (`superset-db`) hosts both the `superset` application database and the `analytics_dw` data warehouse database.

Initialize the `analytics_dw` database and load the multi-tenant dataset (`data/schema.sql`):

```bash
# 1. Create the analytics_dw database
kubectl exec -n superset-bi deployment/superset-db -- psql -U superset -d postgres -c "CREATE DATABASE analytics_dw;"

# 2. Populate dimensions (departments, regions) and fact_orders
# On Windows PowerShell:
Get-Content data/schema.sql -Raw | kubectl exec -i -n superset-bi deployment/superset-db -- psql -U superset -d analytics_dw

# On Linux / macOS / Git Bash:
kubectl exec -i -n superset-bi deployment/superset-db -- psql -U superset -d analytics_dw < data/schema.sql
```

Verify that the sample orders are loaded across FIN, SLS, and OPS departments:

```bash
kubectl exec -n superset-bi deployment/superset-db -- psql -U superset -d analytics_dw -c "SELECT department_code, count(*) as total_orders, sum(order_amount) as total_revenue FROM fact_orders GROUP BY department_code;"
```

---

## Part 3: Local Port Forwarding

In separate terminal windows, expose the web services to your local machine:

```bash
# Terminal 1: Apache Superset Web Interface
kubectl port-forward svc/superset -n superset-bi 8088:8088

# Terminal 2: Keycloak Admin and SSO Broker
kubectl port-forward svc/keycloak -n superset-bi 8080:8080

# Terminal 3: phpLDAPadmin Directory Management GUI
kubectl port-forward svc/phpldapadmin -n superset-bi 8085:80
```

---

## Part 4: Managing LDAP Users via phpLDAPadmin (Manual Web UI Guide)

You can inspect directory objects, create new users, and assign them to department groups using phpLDAPadmin.

### 4.1 Log In to phpLDAPadmin
1. Navigate to: [http://localhost:8085](http://localhost:8085)
2. In the left navigation panel, click **Login**:
   * **Login DN**: `cn=admin,dc=example,dc=org`
   * **Password**: `adminpassword`
3. Click **Authenticate**.

### 4.2 Inspect the Directory Structure
In the left navigation tree, expand `+ dc=example,dc=org`:
* **`ou=groups`**: Contains role groups (`cn=bi-admins`, `cn=bi-analysts`, `cn=bi-finance-viewers`, `cn=bi-sales-viewers`).
* **`ou=users`**: Contains active user entries.

![phpLDAPadmin Directory Tree](docs/images/04_phpldapadmin_groups_tree.png)

### 4.3 Step-by-Step: Create a New User and Assign Roles
Follow these steps to manually add a new user and assign them to an LDAP group:

1. **Create the User Account**:
   * In the left panel, click on **`ou=users`**.
   * In the main right pane, click **"Create a child entry"**.
   * Select **"Generic: User Account"** (or `inetOrgPerson`).
   * Enter the user details:
     * **First name (givenName)**: `Mehmet`
     * **Last name (sn)**: `Admin`
     * **Common Name (cn)**: `Mehmet Admin`
     * **User ID (uid)**: `mehmet.admin` (This is the login username).
     * **Email (mail)**: `mehmet.admin@example.org`
     * **Password (userPassword)**: `Password123!`
   * Click **Create Object**, then click **Commit**.

2. **Assign the User to a Department Group**:
   * In the left tree under `ou=groups`, click directly on the desired group (for example, **`cn=bi-admins`** for administrator access, or **`cn=bi-finance-viewers`** for finance access).
   * In the right pane, locate the **`member`** attribute.
   * Click the blue **`(add value)`** link directly below the `member` field.
   * Paste the full Distinguished Name (DN) of the new user:
     ```text
     uid=mehmet.admin,ou=users,dc=example,dc=org
     ```
   * Click the **"Update Object"** button at the bottom of the page to save.

---

## Part 5: Single Sign-On Authentication via Keycloak

### 5.1 Sign In with Keycloak
1. Open your browser and navigate to: [http://localhost:8088](http://localhost:8088)
2. On the Superset sign-in page, click the **"SIGN IN WITH KEYCLOAK"** button:

![Superset Sign In with Keycloak](docs/images/01_superset_signin_button.png)

3. Superset redirects your browser to the Keycloak authentication screen.

### 5.2 Enter Credentials
On the Keycloak login screen:
* In **Username or email**, enter your LDAP username (such as `john.admin`, `bob.finance`, or your newly created user).
* In **Password**, enter: `Password123!`
* Click **Sign In**:

![Keycloak Authentication Screen](docs/images/02_keycloak_login.png)

### 5.3 Dynamic User Creation and Role Synchronization
Upon authentication:
1. Keycloak validates the password against OpenLDAP, retrieves the user's groups, and generates a signed OIDC token with the `groups` claim.
2. Superset's `CustomSsoSecurityManager` decodes the token, creates the user account on first login, and maps LDAP groups to Superset roles.
3. Log in as an administrator (`john.admin`) and navigate to **Settings > List Users** to view all synchronized users and their assigned roles:

![Superset Synchronized User Roles List](docs/images/03_superset_synced_users.png)

---

## Part 6: Configuring Data Governance & RLS in Superset (Manual Web UI Guide)

Access control and data isolation are managed directly in the Apache Superset Web UI.

### 6.1 Connect Database in Superset UI
1. Log in as an Administrator (`john.admin`).
2. Go to **Settings > Database Connections** (top right gear icon).
3. Click the **+ Database** button.
4. Select **PostgreSQL** and enter the connection details:
   * **Database Name**: `Analytics Data Warehouse`
   * **SQLAlchemy URI**:
     ```text
     postgresql+psycopg2://superset:supersetpassword@superset-db.superset-bi.svc.cluster.local:5432/analytics_dw
     ```
5. Click **Connect**, then click **Finish**.

### 6.2 Register Dataset in Superset UI
1. Go to **Datasets** in the top navigation bar.
2. Click the **+ Dataset** button.
3. In the modal:
   * **Database**: `Analytics Data Warehouse`
   * **Schema**: `public`
   * **Table**: `fact_orders`
4. Click **Create Dataset and Create Chart**.
5. **Configure Saved Metrics (Recommended for easy sorting and reuse)**:
   * Navigate to **Datasets**, locate `public.fact_orders`, and click the **Edit** (pencil) icon.
   * Switch to the **Metrics** tab and click **+ Add Metric**:
     * **Metric Name**: `total_revenue` | **SQL Expression**: `SUM(order_amount)`
   * Click **+ Add Metric** again:
     * **Metric Name**: `total_profit` | **SQL Expression**: `SUM(profit)`
   * Click **Save**. These metrics will now appear in the **Saved** metrics tab and will be directly selectable in the **Sort By** dropdown in all charts.

### 6.3 Configure Row-Level Security (RLS) Rules in Superset UI

> [!NOTE]
> Custom department roles (`Finance_Viewers`, `Sales_Viewers`) are provisioned automatically when department users (such as `bob.finance` or `carol.sales`) log in via Keycloak SSO for the first time. To register them beforehand, navigate to **Settings > List Roles**, click **+**, enter the role name, and click **Save**.

1. Go to **Settings > Row Level Security**.
2. Click the **+ Rule** button to create the Finance filter:
   * **Rule Name**: `Finance Department Filter`
   * **Filter Type**: `Regular`
   * **Tables**: `fact_orders`
   * **Roles**: `Finance_Viewers`
   * **Clause**: `department_code = 'FIN'`
   * Click **Save**.
3. Click the **+ Rule** button to create the Sales filter:
   * **Rule Name**: `Sales Department Filter`
   * **Filter Type**: `Regular`
   * **Tables**: `fact_orders`
   * **Roles**: `Sales_Viewers`
   * **Clause**: `department_code = 'SLS'`
   * Click **Save**.

### 6.4 Create Visual Charts (Slices) in Superset UI

Each of the three role-partitioned dashboards contains two dedicated visualizations: an **aggregated summary chart** and a **detailed audit ledger**.

Follow the generic creation workflow below, then apply the specific field configuration for each chart.

#### General Chart Creation Workflow
1. In the top navigation bar, click **+ > Chart** (or go to **Charts** and click **+ Chart**).
2. Under **1 Choose a dataset**, select `public.fact_orders`.
3. Under **2 Choose chart type**, select **Table** (or **Bar Chart**):

![Superset Create Chart Wizard](docs/images/05_superset_create_chart.png)

4. Click **Create New Chart** to enter the Chart Builder (Explore) view:

![Superset Chart Builder](docs/images/06_superset_chart_builder.png)

5. Configure query parameters (Query Mode, Dimensions, Metrics, or Columns).
6. Click **Update Chart** (or Ctrl + Enter) to run the query and preview the visualization.
7. Click **Save** in the top right corner:
   * Enter the **Chart Name**.
   * Under **Add to Dashboard**, select or type the destination dashboard title.
   * Click **Save & Go to Dashboard** (or **Save**).

---

#### Field Specifications for All Dashboard Charts

##### 1. Finance Performance Dashboard Charts

* **Chart 1: Finance Revenue by Product Category**
  * **Visualization Type**: `Table`
  * **Query Mode**: `AGGREGATE`
  * **Dimensions (Group by)**: `product_category`
  * **Metrics**:
    * `order_amount` -> Aggregate: `SUM`, Custom Label: `total_revenue`
    * `profit` -> Aggregate: `SUM`, Custom Label: `total_profit`
    * `COUNT(*)` (row count)
  * **Sort By**: `total_revenue` (Descending)
  * **Row Limit**: `100`
  * **Add to Dashboard**: `Finance Performance Dashboard`

* **Chart 2: Finance Transactions Ledger**
  * **Visualization Type**: `Table`
  * **Query Mode**: `RAW RECORDS`
  * **Columns**: `order_id`, `order_date`, `customer_name`, `product_category`, `order_amount`, `cost_amount`, `profit`
  * **Sort By**: `order_id` (Descending)
  * **Row Limit**: `500`
  * **Add to Dashboard**: `Finance Performance Dashboard`

---

##### 2. Sales Revenue Dashboard Charts

* **Chart 3: Sales Regional Performance**
  * **Visualization Type**: `Table` (or `Bar Chart`)
  * **Query Mode**: `AGGREGATE`
  * **Dimensions (Group by)**: `region_code`
  * **Metrics**:
    * `order_amount` -> Aggregate: `SUM`, Custom Label: `total_revenue`
    * `profit` -> Aggregate: `SUM`, Custom Label: `total_profit`
    * `COUNT(*)`
  * **Sort By**: `total_revenue` (Descending)
  * **Row Limit**: `100`
  * **Add to Dashboard**: `Sales Revenue Dashboard`

* **Chart 4: Sales Orders Ledger**
  * **Visualization Type**: `Table`
  * **Query Mode**: `RAW RECORDS`
  * **Columns**: `order_id`, `order_date`, `customer_name`, `region_code`, `order_amount`, `cost_amount`, `profit`
  * **Sort By**: `order_id` (Descending)
  * **Row Limit**: `500`
  * **Add to Dashboard**: `Sales Revenue Dashboard`

---

##### 3. Executive Enterprise Overview Charts

* **Chart 5: Enterprise Department Performance**
  * **Visualization Type**: `Table` (or `Bar Chart`)
  * **Query Mode**: `AGGREGATE`
  * **Dimensions (Group by)**: `department_code`
  * **Metrics**:
    * `order_amount` -> Aggregate: `SUM`, Custom Label: `total_revenue`
    * `profit` -> Aggregate: `SUM`, Custom Label: `total_profit`
    * `COUNT(*)`
  * **Sort By**: `total_revenue` (Descending)
  * **Row Limit**: `100`
  * **Add to Dashboard**: `Executive Enterprise Overview`

* **Chart 6: Enterprise All Orders Ledger**
  * **Visualization Type**: `Table`
  * **Query Mode**: `RAW RECORDS`
  * **Columns**: `order_id`, `order_date`, `department_code`, `region_code`, `customer_name`, `product_category`, `order_amount`, `cost_amount`, `profit`
  * **Sort By**: `order_id` (Descending)
  * **Row Limit**: `1000`
  * **Add to Dashboard**: `Executive Enterprise Overview`

### 6.5 Assemble and Publish Dashboards in Superset UI
1. Navigate to **Dashboards** in the top navigation bar to view all registered dashboards:

![Superset Dashboards List](docs/images/07_superset_dashboards_list.png)

2. Click on a dashboard (such as **Finance Performance Dashboard**) to open it:
   * The dashboard renders the configured tables, metrics, and KPI aggregations.
   * Row-Level Security automatically filters data based on the authenticated user's department.

![Superset Rendered Dashboard View](docs/images/09_superset_finance_dashboard.png)

3. To rearrange or add new components, click **Edit Dashboard** (top right) and drag layout elements (Rows, Columns, Tabs, Header) from the right sidebar. Click **Save** when finished.

### 6.6 Enforce Dashboard Access Control (RBAC) in Superset UI
Because `DASHBOARD_RBAC` is enabled, only users possessing authorized roles can see or open specific dashboards:

1. From the **Dashboards** list, locate the dashboard row and click the pencil/edit icon (or open the dashboard and click the three dots menu `...` > **Edit dashboard properties**).
2. In the **Access** section, locate the **Roles** field:
   * For the **Finance Performance Dashboard**, add the **`Finance_Viewers`** role.
   * For the **Sales Revenue Dashboard**, add the **`Sales_Viewers`** role.
   * For the **Executive Enterprise Overview**, add the **`Admin`** and **`Alpha`** roles.

![Superset Dashboard RBAC Properties](docs/images/08_superset_dashboard_rbac_modal.png)

3. Click **Save** to persist the role assignment. Users lacking these roles will not see the dashboard in their list or have access to view its contents.

---

## Part 7: Testing Access Control and Row-Level Security

Test the security partitioning manually using different personas in separate Incognito / Private browser windows:

### Test Case 1: BI Administrator (`john.admin`)
1. Open a new private browser window and navigate to [http://localhost:8088](http://localhost:8088).
2. Sign in with `john.admin` / `Password123!`.
3. **Verify Results**:
   * Can access all dashboards (Executive, Finance, Sales).
   * Full access to **SQL Lab** (can write arbitrary SQL queries).
   * Views all 11 orders with total revenue of $2,615,000 across FIN, SLS, and OPS.

### Test Case 2: Finance Viewer (`bob.finance`)
1. Open a fresh private browser window and navigate to [http://localhost:8088](http://localhost:8088).
2. Sign in with `bob.finance` / `Password123!`.
3. **Verify Results**:
   * Visible Dashboards: Only the **Finance Performance Dashboard** appears in the list.
   * SQL Lab access is **completely removed/blocked** from the navigation bar.
   * When viewing charts, only 4 Finance orders are visible ($865,000 revenue). Sales and Operations data are masked out by the RLS database filter.

### Test Case 3: Sales Viewer (`carol.sales`)
1. Open a fresh private browser window and navigate to [http://localhost:8088](http://localhost:8088).
2. Sign in with `carol.sales` / `Password123!`.
3. **Verify Results**:
   * Visible Dashboards: Only the **Sales Revenue Dashboard** appears.
   * SQL Lab access is **completely removed/blocked**.
   * When viewing charts, only 4 Sales orders are visible ($630,000 revenue). Finance and Operations data are masked out.

---

## Part 8: Platform Teardown via kubectl

To tear down all deployed Kubernetes resources:

```bash
# Delete all workloads, services, and policies (preserves persistent volume data)
kubectl delete -k deploy/k8s

# Or completely purge the namespace and all associated volumes
kubectl delete namespace superset-bi
```

---

## Repository Structure

```
├── AGENTS.MD                               # System requirements and autonomous agent blueprint
├── README.md                               # Operational guide and platform documentation
├── .gitignore                              # Git ignore rules for secrets and temporary files
├── data/
│   └── schema.sql                          # Analytics DW schema and mock orders seed
├── deploy/
│   └── k8s/                                # Kubernetes manifests (Kustomize)
│       ├── kustomization.yaml              # Master Kustomize file
│       ├── namespace.yaml                  # 'superset-bi' namespace specification
│       ├── secrets.yaml                    # Base64 credentials abstraction
│       ├── ingress.yaml                    # Ingress resource for web, SSO, and LDAP UI
│       ├── network-policies.yaml           # Zero-trust inter-pod network isolation
│       ├── ldap/                           # OpenLDAP and phpLDAPadmin manifests
│       │   ├── configmap.yaml
│       │   ├── deployment.yaml
│       │   ├── phpldapadmin.yaml
│       │   ├── pvc.yaml
│       │   └── service.yaml
│       ├── keycloak/                       # Keycloak and Keycloak-DB manifests
│       │   ├── deployment.yaml
│       │   ├── postgres-deployment.yaml
│       │   ├── postgres-pvc.yaml
│       │   ├── postgres-service.yaml
│       │   ├── realm-configmap.yaml
│       │   └── service.yaml
│       └── superset/                       # Superset web, worker, db, redis, init-job
│           ├── configmap.yaml
│           ├── db-deployment.yaml
│           ├── db-pvc.yaml
│           ├── db-service.yaml
│           ├── init-job.yaml
│           ├── redis-deployment.yaml
│           ├── redis-service.yaml
│           ├── service.yaml
│           ├── web-deployment.yaml
│           └── worker-deployment.yaml
├── docs/
│   └── images/                             # Instructional screenshots
│       ├── 01_superset_signin_button.png
│       ├── 02_keycloak_login.png
│       ├── 03_superset_synced_users.png
│       ├── 04_phpldapadmin_groups_tree.png
│       ├── 05_superset_create_chart.png
│       ├── 06_superset_chart_builder.png
│       ├── 07_superset_dashboards_list.png
│       ├── 08_superset_dashboard_rbac_modal.png
│       └── 09_superset_finance_dashboard.png
└── superset/
    ├── config/
    │   └── superset_config.py              # Superset configuration with OAuth provider
    └── security/
        └── custom_sso_security_manager.py  # Custom FAB Security Manager
```
