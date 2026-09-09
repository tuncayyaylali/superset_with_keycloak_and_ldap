import sys
from superset.app import create_app

app = create_app()

with app.app_context():
    from superset import db
    from superset.models.core import Database
    from superset.connectors.sqla.models import SqlaTable, RowLevelSecurityFilter
    from superset.models.dashboard import Dashboard
    from flask_appbuilder.security.sqla.models import Role

    print("==========================================================")
    print(" [Superset Governance] Configuring Database, RLS, and RBAC")
    print("==========================================================")

    # 1. Register Database Connection (Analytics Data Warehouse)
    db_name = "Analytics Data Warehouse"
    uri = "postgresql+psycopg2://superset:supersetpassword@superset-db.superset-bi.svc.cluster.local:5432/analytics_dw"
    
    db_obj = db.session.query(Database).filter_by(database_name=db_name).first()
    if not db_obj:
        print(f"Creating database connection '{db_name}'...")
        db_obj = Database(database_name=db_name, sqlalchemy_uri=uri)
        db.session.add(db_obj)
        db.session.commit()
        print(f"[OK] Database '{db_name}' created (ID: {db_obj.id}).")
    else:
        print(f"[OK] Database '{db_name}' already exists (ID: {db_obj.id}).")

    # 2. Register Dataset 'fact_orders'
    table_name = "fact_orders"
    table_obj = db.session.query(SqlaTable).filter_by(table_name=table_name, database_id=db_obj.id).first()
    if not table_obj:
        print(f"Registering dataset '{table_name}'...")
        table_obj = SqlaTable(table_name=table_name, database_id=db_obj.id, schema="public")
        db.session.add(table_obj)
        db.session.commit()
        try:
            table_obj.fetch_metadata()
            db.session.commit()
        except Exception as e:
            print(f"Metadata fetch warning: {e}")
        print(f"[OK] Dataset '{table_name}' registered (ID: {table_obj.id}).")
    else:
        print(f"[OK] Dataset '{table_name}' already registered (ID: {table_obj.id}).")

    # 3. Retrieve Roles for RLS and Dashboard RBAC
    sm = app.appbuilder.sm
    role_admin = sm.find_role("Admin")
    role_alpha = sm.find_role("Alpha")
    role_fin = sm.find_role("Finance_Viewers")
    if not role_fin:
        role_fin = sm.add_role("Finance_Viewers")
    role_sls = sm.find_role("Sales_Viewers")
    if not role_sls:
        role_sls = sm.add_role("Sales_Viewers")

    print(f"Roles confirmed: Finance_Viewers (ID: {role_fin.id}), Sales_Viewers (ID: {role_sls.id})")

    # 4. Configure Row Level Security (RLS) Filters
    # RLS Filter for Finance Viewers: department_code = 'FIN'
    rls_fin = db.session.query(RowLevelSecurityFilter).filter_by(name="rls_finance_department").first()
    if not rls_fin:
        print("Creating RLS filter 'rls_finance_department'...")
        rls_fin = RowLevelSecurityFilter(
            name="rls_finance_department",
            description="Row level restriction for Finance viewers",
            clause="department_code = 'FIN'",
            filter_type="Regular",
            tables=[table_obj],
            roles=[role_fin]
        )
        db.session.add(rls_fin)
    else:
        rls_fin.clause = "department_code = 'FIN'"
        rls_fin.tables = [table_obj]
        rls_fin.roles = [role_fin]
    print("[OK] RLS Filter 'rls_finance_department' mapped to 'Finance_Viewers' with clause: department_code = 'FIN'")

    # RLS Filter for Sales Viewers: department_code = 'SLS'
    rls_sls = db.session.query(RowLevelSecurityFilter).filter_by(name="rls_sales_department").first()
    if not rls_sls:
        print("Creating RLS filter 'rls_sales_department'...")
        rls_sls = RowLevelSecurityFilter(
            name="rls_sales_department",
            description="Row level restriction for Sales viewers",
            clause="department_code = 'SLS'",
            filter_type="Regular",
            tables=[table_obj],
            roles=[role_sls]
        )
        db.session.add(rls_sls)
    else:
        rls_sls.clause = "department_code = 'SLS'"
        rls_sls.tables = [table_obj]
        rls_sls.roles = [role_sls]
    print("[OK] RLS Filter 'rls_sales_department' mapped to 'Sales_Viewers' with clause: department_code = 'SLS'")

    db.session.commit()

    # 5. Create Dashboards with DASHBOARD_RBAC
    # Dashboard 1: Finance Performance Dashboard -> Finance_Viewers
    dash_fin = db.session.query(Dashboard).filter_by(slug="finance-dashboard").first()
    if not dash_fin:
        dash_fin = Dashboard(
            dashboard_title="Finance Performance Dashboard",
            slug="finance-dashboard",
            published=True,
            roles=[role_fin]
        )
        db.session.add(dash_fin)
    else:
        dash_fin.roles = [role_fin]
        dash_fin.published = True
    print("[OK] Dashboard 'Finance Performance Dashboard' bound to role: Finance_Viewers")

    # Dashboard 2: Sales Revenue Dashboard -> Sales_Viewers
    dash_sls = db.session.query(Dashboard).filter_by(slug="sales-dashboard").first()
    if not dash_sls:
        dash_sls = Dashboard(
            dashboard_title="Sales Revenue Dashboard",
            slug="sales-dashboard",
            published=True,
            roles=[role_sls]
        )
        db.session.add(dash_sls)
    else:
        dash_sls.roles = [role_sls]
        dash_sls.published = True
    print("[OK] Dashboard 'Sales Revenue Dashboard' bound to role: Sales_Viewers")

    # Dashboard 3: Executive Enterprise Overview -> Admin and Alpha
    dash_exec = db.session.query(Dashboard).filter_by(slug="executive-overview").first()
    if not dash_exec:
        dash_exec = Dashboard(
            dashboard_title="Executive Enterprise Overview",
            slug="executive-overview",
            published=True,
            roles=[role_admin, role_alpha]
        )
        db.session.add(dash_exec)
    else:
        dash_exec.roles = [role_admin, role_alpha]
        dash_exec.published = True
    print("[OK] Dashboard 'Executive Enterprise Overview' bound to roles: Admin, Alpha")

    db.session.commit()

    print("==========================================================")
    print(" [GOVERNANCE CONFIGURATION COMPLETE]")
    print("==========================================================")

