# Enterprise Access Control & Row-Level Security (RLS) Matrix

This matrix formalizes the data governance and access control model for the Business Intelligence platform. It maps the full chain from directory master (**OpenLDAP**) through the identity broker (**Keycloak**) to the presentation layer (**Apache Superset**), detailing Dashboard RBAC and Row-Level Security (RLS) filters.

---

## Access Control & Governance Matrix

| LDAP Group | Primary Personas | Keycloak Group Claim | Superset Mapped Roles | Allowed Dashboards (`DASHBOARD_RBAC`) | SQL Lab Access | Table: `fact_orders` RLS Clause | Data Governance Scope |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| `cn=bi-admins,ou=groups,dc=example,dc=org` | `john.admin` | `["bi-admins"]` | `Admin` | All Dashboards (Executive, Finance, Sales) | **Full** (`can_sqllab`, write) | *None* (Unrestricted full table scan) | Full enterprise visibility across FIN, SLS, OPS. Unmasked financials and margins. |
| `cn=bi-analysts,ou=groups,dc=example,dc=org` | `alice.analyst` | `["bi-analysts"]` | `Alpha` | All Dashboards (Executive, Finance, Sales) | **Full** (Query authoring, dataset creation) | *None* (Cross-department analytical queries) | Ad-hoc analytics, dataset modeling, cross-department aggregation. |
| `cn=bi-finance-viewers,ou=groups,dc=example,dc=org` | `bob.finance` | `["bi-finance-viewers"]` | `Gamma`, `Finance_Viewers` | **Finance Performance Dashboard** only | **Denied** (No `can_sqllab`, no write) | `department_code = 'FIN'` | Strictly constrained to Finance division. Automatic denial of Sales and Operations transaction records. |
| `cn=bi-sales-viewers,ou=groups,dc=example,dc=org` | `carol.sales` | `["bi-sales-viewers"]` | `Gamma`, `Sales_Viewers` | **Sales Revenue Dashboard** only | **Denied** (No `can_sqllab`, no write) | `department_code = 'SLS'` | Strictly constrained to Sales division. Automatic denial of Finance and Operations transaction records. |

---

## Security Invariants & Policy Enforcement

1. **Least Privilege Principle**:
   - Users associated with `bi-finance-viewers` or `bi-sales-viewers` are automatically stripped of `Admin` and `Alpha` roles by `CustomSsoSecurityManager.auth_user_oauth`.
   - `Gamma` role grants read-only access to published charts/dashboards assigned to their team roles.
2. **Dashboard RBAC Isolation**:
   - Dashboards are explicitly assigned to target roles using the `roles` relationship in Superset metadata.
   - When a user views the Dashboards list, Superset's RBAC filtering hides dashboards not associated with their assigned roles.
3. **Database-Level Predicate Injection (RLS)**:
   - Superset's SQLLab and Chart rendering engine automatically intercepts the SQL query generation AST and appends the mandatory `WHERE` clause:
     ```sql
     WHERE ... AND (department_code = 'FIN')  -- For Finance_Viewers
     WHERE ... AND (department_code = 'SLS')  -- For Sales_Viewers
     ```
   - Even if a viewer crafts or alters a chart filter, the RLS predicate cannot be circumvented.

