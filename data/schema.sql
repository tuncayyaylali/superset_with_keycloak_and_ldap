-- ==============================================================================
-- Business Analytics Warehouse: DDL & Mock Data
-- Database: analytics_dw
-- Purpose: Multi-tenant / Department-level data governance and RLS testing
-- ==============================================================================

DROP TABLE IF EXISTS fact_orders;
DROP TABLE IF EXISTS dim_departments;
DROP TABLE IF EXISTS dim_regions;

-- 1. Department Dimension
CREATE TABLE dim_departments (
    department_code VARCHAR(10) PRIMARY KEY,
    department_name VARCHAR(100) NOT NULL,
    division        VARCHAR(50) NOT NULL
);

INSERT INTO dim_departments (department_code, department_name, division) VALUES
('FIN', 'Finance & Accounting', 'Corporate Services'),
('SLS', 'Sales & Commercial', 'Revenue Operations'),
('OPS', 'Global Operations', 'Infrastructure');

-- 2. Region Dimension
CREATE TABLE dim_regions (
    region_code VARCHAR(10) PRIMARY KEY,
    region_name VARCHAR(50) NOT NULL
);

INSERT INTO dim_regions (region_code, region_name) VALUES
('NA',   'North America'),
('EU',   'Europe & UK'),
('APAC', 'Asia Pacific');

-- 3. Fact Orders Table
CREATE TABLE fact_orders (
    order_id         SERIAL PRIMARY KEY,
    order_date       DATE NOT NULL,
    department_code  VARCHAR(10) NOT NULL REFERENCES dim_departments(department_code),
    region_code      VARCHAR(10) NOT NULL REFERENCES dim_regions(region_code),
    customer_name    VARCHAR(100) NOT NULL,
    product_category VARCHAR(50) NOT NULL,
    order_amount     NUMERIC(12, 2) NOT NULL,
    cost_amount      NUMERIC(12, 2) NOT NULL,
    profit           NUMERIC(12, 2) NOT NULL
);

-- Seed Data: Finance Department (FIN)
INSERT INTO fact_orders (order_date, department_code, region_code, customer_name, product_category, order_amount, cost_amount, profit) VALUES
('2026-01-15', 'FIN', 'NA',   'Acme Capital Ltd',        'Treasury Audit',       150000.00,  45000.00, 105000.00),
('2026-02-10', 'FIN', 'EU',   'Bavaria Holdings AG',     'Tax Advisory',         220000.00,  70000.00, 150000.00),
('2026-03-05', 'FIN', 'APAC', 'Tokyo FinTech Corp',     'ERP Financial Suite',  310000.00,  95000.00, 215000.00),
('2026-04-18', 'FIN', 'NA',   'Delaware Mutual',         'Risk Modeling',        185000.00,  55000.00, 130000.00);

-- Seed Data: Sales Department (SLS)
INSERT INTO fact_orders (order_date, department_code, region_code, customer_name, product_category, order_amount, cost_amount, profit) VALUES
('2026-01-20', 'SLS', 'NA',   'Global Retail Partners',  'Enterprise CRM',        95000.00,  30000.00,  65000.00),
('2026-02-14', 'SLS', 'EU',   'Nordic SupplyChain OY',   'Sales Automation',     140000.00,  42000.00,  98000.00),
('2026-03-22', 'SLS', 'APAC', 'Pacific Distribution',    'Omnichannel License',  275000.00,  80000.00, 195000.00),
('2026-04-29', 'SLS', 'NA',   'Apex Logistics',          'Commerce Portal',      120000.00,  38000.00,  82000.00);

-- Seed Data: Operations Department (OPS)
INSERT INTO fact_orders (order_date, department_code, region_code, customer_name, product_category, order_amount, cost_amount, profit) VALUES
('2026-01-25', 'OPS', 'NA',   'Cloud Core Infrastructure', 'Data Center Hosting', 450000.00, 210000.00, 240000.00),
('2026-02-28', 'OPS', 'EU',   'Trans-European Network',    'Edge CDN Nodes',      380000.00, 160000.00, 220000.00),
('2026-03-15', 'OPS', 'APAC', 'Singapore Cloud Gateway',   'Bandwidth Transit',   290000.00, 120000.00, 170000.00);

