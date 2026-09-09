import json
import uuid
from superset.app import create_app

app = create_app()

def build_dashboard_layout(slices, dashboard_title):
    root_id = "ROOT_ID"
    grid_id = "GRID_ID"
    header_id = "HEADER_ID"

    layout = {
        "DASHBOARD_VERSION_KEY": "v2",
        root_id: {"type": "ROOT", "id": root_id, "children": [grid_id]},
        grid_id: {"type": "GRID", "id": grid_id, "children": [], "parents": [root_id]},
        header_id: {"type": "HEADER", "id": header_id, "meta": {"text": dashboard_title}}
    }

    for idx, s in enumerate(slices):
        row_id = f"ROW-{idx}"
        chart_id = f"CHART-{s.id}"
        layout[grid_id]["children"].append(row_id)
        layout[row_id] = {
            "type": "ROW",
            "id": row_id,
            "children": [chart_id],
            "parents": [root_id, grid_id],
            "meta": {"background": "BACKGROUND_TRANSPARENT"}
        }
        layout[chart_id] = {
            "type": "CHART",
            "id": chart_id,
            "parents": [root_id, grid_id, row_id],
            "children": [],
            "meta": {
                "chartId": s.id,
                "width": 12,
                "height": 50,
                "sliceName": s.slice_name
            }
        }
    return json.dumps(layout)

with app.app_context():
    from superset import db
    from superset.models.slice import Slice
    from superset.models.dashboard import Dashboard
    from superset.connectors.sqla.models import SqlaTable

    tbl = db.session.query(SqlaTable).filter_by(table_name="fact_orders").first()
    if not tbl:
        print("[ERROR] fact_orders table not found!")
        exit(1)

    print(f"Using dataset: {tbl.table_name} (ID: {tbl.id})")

    # Helper to get or create slice
    def get_or_create_slice(name, viz_type, params):
        s = db.session.query(Slice).filter_by(slice_name=name).first()
        if not s:
            s = Slice(
                slice_name=name,
                viz_type=viz_type,
                datasource_type="table",
                datasource_id=tbl.id,
                params=json.dumps(params)
            )
            db.session.add(s)
            db.session.commit()
            print(f"[CREATED] Slice: '{name}' (ID: {s.id})")
        else:
            s.params = json.dumps(params)
            s.viz_type = viz_type
            db.session.commit()
            print(f"[EXISTS] Slice: '{name}' (ID: {s.id})")
        return s

    # 1. FINANCE DASHBOARD SLICES
    fin_summary_params = {
        "viz_type": "table",
        "datasource": f"{tbl.id}__table",
        "query_mode": "aggregate",
        "groupby": ["product_category"],
        "metrics": ["total_revenue", "total_profit", "count"],
        "row_limit": 100,
        "order_desc": True
    }
    s_fin_summary = get_or_create_slice("Finance Revenue by Product Category", "table", fin_summary_params)

    fin_detail_params = {
        "viz_type": "table",
        "datasource": f"{tbl.id}__table",
        "query_mode": "raw",
        "all_columns": ["order_id", "order_date", "customer_name", "product_category", "order_amount", "cost_amount", "profit"],
        "order_by_cols": [["order_id", True]],
        "row_limit": 500
    }
    s_fin_detail = get_or_create_slice("Finance Transactions Ledger", "table", fin_detail_params)

    # 2. SALES DASHBOARD SLICES
    sales_summary_params = {
        "viz_type": "table",
        "datasource": f"{tbl.id}__table",
        "query_mode": "aggregate",
        "groupby": ["region_code"],
        "metrics": ["total_revenue", "total_profit", "count"],
        "row_limit": 100,
        "order_desc": True
    }
    s_sales_summary = get_or_create_slice("Sales Regional Performance", "table", sales_summary_params)

    sales_detail_params = {
        "viz_type": "table",
        "datasource": f"{tbl.id}__table",
        "query_mode": "raw",
        "all_columns": ["order_id", "order_date", "customer_name", "region_code", "order_amount", "cost_amount", "profit"],
        "order_by_cols": [["order_id", True]],
        "row_limit": 500
    }
    s_sales_detail = get_or_create_slice("Sales Orders Ledger", "table", sales_detail_params)

    # 3. EXECUTIVE DASHBOARD SLICES
    exec_summary_params = {
        "viz_type": "table",
        "datasource": f"{tbl.id}__table",
        "query_mode": "aggregate",
        "groupby": ["department_code"],
        "metrics": ["total_revenue", "total_profit", "count"],
        "row_limit": 100,
        "order_desc": True
    }
    s_exec_summary = get_or_create_slice("Enterprise Department Performance", "table", exec_summary_params)

    exec_detail_params = {
        "viz_type": "table",
        "datasource": f"{tbl.id}__table",
        "query_mode": "raw",
        "all_columns": ["order_id", "order_date", "department_code", "region_code", "customer_name", "product_category", "order_amount", "cost_amount", "profit"],
        "order_by_cols": [["order_id", True]],
        "row_limit": 1000
    }
    s_exec_detail = get_or_create_slice("Enterprise All Orders Ledger", "table", exec_detail_params)

    # Attach Slices and Layouts to Dashboards
    dash_fin = db.session.query(Dashboard).filter_by(slug="finance-dashboard").first()
    if dash_fin:
        dash_fin.slices = [s_fin_summary, s_fin_detail]
        dash_fin.position_json = build_dashboard_layout([s_fin_summary, s_fin_detail], dash_fin.dashboard_title)
        print(f"[UPDATED] Dashboard '{dash_fin.dashboard_title}' with 2 slices and layout.")

    dash_sls = db.session.query(Dashboard).filter_by(slug="sales-dashboard").first()
    if dash_sls:
        dash_sls.slices = [s_sales_summary, s_sales_detail]
        dash_sls.position_json = build_dashboard_layout([s_sales_summary, s_sales_detail], dash_sls.dashboard_title)
        print(f"[UPDATED] Dashboard '{dash_sls.dashboard_title}' with 2 slices and layout.")

    dash_exec = db.session.query(Dashboard).filter_by(slug="executive-overview").first()
    if dash_exec:
        dash_exec.slices = [s_exec_summary, s_exec_detail]
        dash_exec.position_json = build_dashboard_layout([s_exec_summary, s_exec_detail], dash_exec.dashboard_title)
        print(f"[UPDATED] Dashboard '{dash_exec.dashboard_title}' with 2 slices and layout.")

    db.session.commit()
    print("[SUCCESS] All dashboards populated with charts and layouts!")

