# Snowflake Data Pipeline with dbt and Airflow

This project demonstrates how to build a complete data pipeline using **Snowflake**, **dbt**, and **Apache Airflow**. It processes sample TPC-H data from Snowflake's public datasets to create a simple data mart showcasing modern data engineering practices.

## Overview

This pipeline demonstrates:
- **Data Ingestion**: Using Snowflake's sample TPC-H dataset
- **Data Transformation**: dbt models for staging and mart layers
- **Data Testing**: dbt tests for data quality validation
- **Orchestration**: Airflow DAGs using Astronomer Cosmos for dbt integration
- **Data Warehouse**: Snowflake as the cloud data platform

## Architecture

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Snowflake     │    │      dbt        │    │    Airflow      │
│  Sample Data    │───▶│  Transformations│───▶│   Orchestration │
│   (TPC-H)       │    │                 │    │    (Cosmos)     │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

## Prerequisites

1. **Snowflake Account**: Sign up at [snowflake.com](https://snowflake.com)
2. **Astronomer CLI**: Install from [astronomer.io](https://www.astronomer.io/docs/astro/cli/install-cli)
3. **Docker**: Required for local Airflow development

## Setup Instructions

### 1. Snowflake Setup

1. **Create Snowflake Account** and note your account identifier
2. **Create Database and Schema** (run these commands in **Snowflake Web UI** or **SnowSQL CLI**):
   ```sql
   -- Create database for dbt
   CREATE DATABASE dbt_db;
   
   -- Create schema
   CREATE SCHEMA dbt_db.dbt_schema;
   
   -- Create warehouse for dbt operations
   CREATE WAREHOUSE dbt_wh 
   WITH WAREHOUSE_SIZE = 'XSMALL' 
   AUTO_SUSPEND = 60 
   AUTO_RESUME = TRUE;
   ```

3. **Create dbt User** (recommended for production) - run in **Snowflake Web UI** or **SnowSQL CLI**:
   ```sql
   -- Create role for dbt
   CREATE ROLE dbt_role;
   
   -- Grant permissions
   GRANT USAGE ON WAREHOUSE dbt_wh TO ROLE dbt_role;
   GRANT USAGE ON DATABASE dbt_db TO ROLE dbt_role;
   GRANT CREATE SCHEMA ON DATABASE dbt_db TO ROLE dbt_role;
   GRANT USAGE ON SCHEMA dbt_db.dbt_schema TO ROLE dbt_role;
   GRANT CREATE TABLE ON SCHEMA dbt_db.dbt_schema TO ROLE dbt_role;
   GRANT CREATE VIEW ON SCHEMA dbt_db.dbt_schema TO ROLE dbt_role;
   
   -- Create user
   CREATE USER dbt_user 
   PASSWORD = 'your_secure_password'
   DEFAULT_ROLE = dbt_role
   DEFAULT_WAREHOUSE = dbt_wh;
   
   GRANT ROLE dbt_role TO USER dbt_user;
   ```

### 2. Configure Airflow Connection

1. **Update `airflow_settings.yaml`** (edit this file in your **local IDE/text editor**):
   ```yaml
   airflow:
     connections:
       - conn_id: snowflake_conn
         conn_type: snowflake
         conn_host: your_account.snowflakecomputing.com
         conn_schema: dbt_schema
         conn_login: dbt_user
         conn_password: your_secure_password
         conn_extra:
           account: your_account
           warehouse: dbt_wh
           database: dbt_db
           region: your_region
   ```

### 3. Local Development Setup

1. **Start Airflow** (run in your **local terminal**):
   ```bash
   astro dev start
   ```

2. **Access Airflow UI**: http://localhost:8080 (open in your **web browser**)
   - Username: `admin`
   - Password: `admin`

3. **Enable the DAG**: Find `dbt_dag` in the Airflow UI and enable it

## Understanding the Data Pipeline

### Data Source: TPC-H Sample Data

The pipeline uses Snowflake's built-in TPC-H sample dataset (`SNOWFLAKE_SAMPLE_DATA.TPCH_SF1`), which contains:
- **Orders**: Customer order information
- **LineItem**: Individual line items for each order
- **Customer**: Customer details
- **Part**: Product information

### dbt Project Structure

```
dags/dbt/snowflake_data_pipeline/
├── dbt_project.yml          # dbt project configuration
├── models/
│   ├── staging/             # Raw data transformations
│   │   ├── stg_tpch_orders.sql
│   │   ├── stg_tpch_line_items.sql
│   │   └── tpch_sources.yml # Source definitions
│   └── marts/               # Business logic layer
│       ├── fct_orders.sql   # Final fact table
│       ├── int_order_items_summary.sql
│       ├── int_order_items.sql
│       └── generic_tests.yml # Data quality tests
├── macros/
│   └── pricing.sql          # Reusable pricing calculations
└── tests/
    └── fct_orders_discount.sql # Custom data tests
```

### Key dbt Components Explained

#### 1. **Sources (`tpch_sources.yml`)**
Defines connections to raw Snowflake tables and includes **source-level data quality tests**:

```yaml
version: 2

sources:
  - name: tpch
    database: snowflake_sample_data
    schema: tpch_sf1
    tables:
      - name: orders
        columns:
          - name: o_orderkey
            tests:
              - unique        # Ensures each order key is unique
              - not_null      # Ensures no null order keys exist
      - name: lineitem
        columns:
          - name: l_orderkey
            tests:
              - relationships:  # Ensures referential integrity
                  to: source('tpch', 'orders')
                  field: o_orderkey
```

**What this YAML does:**
- **`unique`**: Validates that `o_orderkey` contains only unique values (no duplicates)
- **`not_null`**: Ensures `o_orderkey` never contains NULL values
- **`relationships`**: Validates that every `l_orderkey` in lineitem table has a corresponding `o_orderkey` in orders table (foreign key constraint)

#### 2. **Staging Models**
Clean and standardize raw data:
- **`stg_tpch_orders.sql`**: Renames columns and selects relevant fields from orders
- **`stg_tpch_line_items.sql`**: Processes line item data with pricing calculations

#### 3. **Intermediate Models**
Business logic transformations:
- **`int_order_items.sql`**: Joins line items with product details
- **`int_order_items_summary.sql`**: Aggregates order-level metrics

#### 4. **Mart Models**
Final business-ready tables:
- **`fct_orders.sql`**: Complete order fact table with calculated metrics

#### 5. **Macros (`pricing.sql`)**
Reusable SQL functions:
```sql
{% macro discounted_amount(extended_price, discount_percentage, scale=2) %}
    (-1 * {{ extended_price }} * ({{ discount_percentage }}::decimal(16, {{ scale }})))
{% endmacro %}
```

#### 6. **Model Tests (`generic_tests.yml`)**
**Model-level data quality validations** for the final fact table:

```yaml
models:
  - name: fct_orders
    columns:
      - name: order_key
        tests:
          - unique                    # Each order_key must be unique
          - not_null                  # order_key cannot be NULL
          - relationships:            # Referential integrity check
              to: ref('stg_tpch_orders')
              field: order_key
              severity: warn          # Warning level (won't fail pipeline)
      - name: status_code
        tests:
          - accepted_values:          # Status must be one of these values
              values: ['P', 'O', 'F']
```

**What this YAML does:**
- **`unique`**: Ensures each `order_key` in the fact table appears only once
- **`not_null`**: Validates that `order_key` is never NULL
- **`relationships`**: Confirms every `order_key` in `fct_orders` exists in `stg_tpch_orders` (data lineage validation)
- **`accepted_values`**: Validates that `status_code` only contains 'P' (Pending), 'O' (Open), or 'F' (Fulfilled)
- **`severity: warn`**: Sets test failure to warning level instead of error (allows pipeline to continue)

#### 7. **Custom Tests (`fct_orders_discount.sql`)**
**Custom SQL-based data quality test**:

```sql
select
    *
from {{ref('fct_orders')}}
where item_discount_amount > 0

-- test if there are neg discounts. Can't have a negative.
```

**What this test does:**
- **Business Logic Validation**: Ensures that `item_discount_amount` is never negative
- **Custom Rule**: Tests a specific business rule that discounts cannot be negative
- **Data Quality**: Catches data transformation errors where discount calculations might produce negative values
- **Test Logic**: Returns rows where `item_discount_amount > 0` - if any rows are returned, the test fails (indicating negative discounts exist)

### dbt Configuration (`dbt_project.yml`)

Key settings:
- **Materialization Strategy**:
  - Staging models → Views (fast, up-to-date)
  - Marts models → Tables (optimized for querying)
- **Warehouse Configuration**: Uses `dbt_wh` for all operations

## Running the Pipeline

### Manual dbt Execution (for testing)

Run these commands in your **local terminal** after connecting to the Airflow container:

```bash
# Connect to Airflow container (run in local terminal)
astro dev bash

# Navigate to dbt project (run inside Airflow container)
cd /usr/local/airflow/dags/dbt/snowflake_data_pipeline

# Install dependencies (run inside Airflow container)
dbt deps

# Test connection (run inside Airflow container)
dbt debug

# Run staging models (run inside Airflow container)
dbt run --select staging

# Run all models (run inside Airflow container)
dbt run

# Test data quality (run inside Airflow container)
dbt test

# Generate documentation (run inside Airflow container)
dbt docs generate
```

### Airflow Orchestration

The DAG (`dbt_dag.py`) automatically:
1. **Installs dbt dependencies**
2. **Runs staging models** (as views)
3. **Runs intermediate models**
4. **Runs mart models** (as tables)
5. **Executes data quality tests**

**Schedule**: Daily at midnight (`@daily`)

## Data Outputs

After successful execution, you'll have:

1. **Staging Views**:
   - `dbt_schema.stg_tpch_orders`
   - `dbt_schema.stg_tpch_line_items`

2. **Mart Tables**:
   - `dbt_schema.fct_orders` - Complete order analytics
   - `dbt_schema.int_order_items_summary` - Order-level aggregations

3. **Sample Query** (run in **Snowflake Web UI** or **SnowSQL CLI**):
   ```sql
   SELECT 
       order_key,
       customer_key,
       order_date,
       total_price,
       gross_item_sales_amount,
       item_discount_amount
   FROM dbt_schema.fct_orders
   ORDER BY order_date DESC
   LIMIT 10;
   ```

## Monitoring and Troubleshooting

### Common Issues

1. **Connection Errors**: Verify Snowflake credentials in `airflow_settings.yaml`
2. **Permission Errors**: Ensure dbt user has proper grants
3. **Model Failures**: Check Airflow logs for specific dbt errors

### Useful Commands

Run these commands in your **local terminal**:

```bash
# Check DAG status (run in local terminal)
astro dev bash
airflow dags state dbt_dag

# View task logs (run in local terminal)
airflow tasks logs dbt_dag <task_id> <execution_date>

# Test dbt connection (run inside Airflow container)
dbt debug --target dev
```

## Next Steps

This pipeline demonstrates foundational concepts. To extend it:

1. **Add More Sources**: Connect additional data sources
2. **Implement Incremental Models**: For large datasets
3. **Add Snapshots**: Track slowly changing dimensions
4. **Create Data Marts**: Customer, product, or time-based marts
5. **Implement CI/CD**: Automated testing and deployment
6. **Add Monitoring**: Data quality monitoring and alerting

## Dataset Summary

### Input Datasets (Pre-existing in Snowflake)
- **SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS** - Raw order data
- **SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.LINEITEM** - Raw line item data

### Output Datasets (Created by Airflow DAG)

#### Stage 1: Staging Layer (from raw data)
- **dbt_schema.stg_tpch_orders** - Cleaned order data (View) ← from ORDERS
- **dbt_schema.stg_tpch_line_items** - Cleaned line item data (View) ← from LINEITEM

#### Stage 2: Intermediate Layer (from staging data)
- **dbt_schema.int_order_items** - Joined order items with product details (Table) ← from stg_tpch_line_items
- **dbt_schema.int_order_items_summary** - Order-level aggregations (Table) ← from int_order_items

#### Stage 3: Mart Layer (from staging + intermediate data)
- **dbt_schema.fct_orders** - Final fact table with complete order analytics (Table) ← from stg_tpch_orders + int_order_items_summary

### Data Flow Diagram

```
┌─────────────────────────────────┐    ┌─────────────────────────────────┐    ┌─────────────────────────────────┐
│        INPUT DATASETS            │    │      STAGING LAYER              │    │    INTERMEDIATE LAYER          │
│     (Pre-existing in Snowflake)  │    │   (Created by Airflow DAG)      │    │   (Created by Airflow DAG)      │
├─────────────────────────────────┤    ├─────────────────────────────────┤    ├─────────────────────────────────┤
│ • ORDERS (raw order data)        │───▶│ • stg_tpch_orders (View)         │───▶│ • int_order_items (Table)        │
│ • LINEITEM (raw line items)     │───▶│ • stg_tpch_line_items (View)    │───▶│ • int_order_items_summary (Table) │
└─────────────────────────────────┘    └─────────────────────────────────┘    └─────────────────────────────────┘
                                                                                        │
                                                                                        ▼
                                                                        ┌─────────────────────────────────┐
                                                                        │        MART LAYER                 │
                                                                        │   (Created by Airflow DAG)        │
                                                                        ├─────────────────────────────────┤
                                                                        │ • fct_orders (Table)             │
                                                                        │   ← stg_tpch_orders +              │
                                                                        │     int_order_items_summary        │
                                                                        └─────────────────────────────────┘
```

**Legend:**
- **Views**: Real-time data transformations (fast, always up-to-date)
- **Tables**: Materialized data for optimized querying (better performance)
- **←**: Shows data lineage (what each dataset is created from)

**Data Dependencies:**
1. **Raw Data** → **Staging Views** (cleaning & standardization)
2. **Staging Views** → **Intermediate Tables** (business logic & aggregations)
3. **Staging + Intermediate** → **Mart Tables** (final business-ready analytics)


# Astronomer Project Documentation

Below is the original Astronomer documentation for the underlying Airflow setup:

## Dataset Summary

### Input Datasets (Pre-existing in Snowflake)
- **SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.ORDERS** - Raw order data
- **SNOWFLAKE_SAMPLE_DATA.TPCH_SF1.LINEITEM** - Raw line item data

### Output Datasets (Created by Airflow DAG)

#### Stage 1: Staging Layer (from raw data)
- **dbt_schema.stg_tpch_orders** - Cleaned order data (View) ← from ORDERS
- **dbt_schema.stg_tpch_line_items** - Cleaned line item data (View) ← from LINEITEM

#### Stage 2: Intermediate Layer (from staging data)
- **dbt_schema.int_order_items** - Joined order items with product details (Table) ← from stg_tpch_line_items
- **dbt_schema.int_order_items_summary** - Order-level aggregations (Table) ← from int_order_items

#### Stage 3: Mart Layer (from staging + intermediate data)
- **dbt_schema.fct_orders** - Final fact table with complete order analytics (Table) ← from stg_tpch_orders + int_order_items_summary

### Data Flow Diagram

```
┌─────────────────────────────────┐    ┌─────────────────────────────────┐    ┌─────────────────────────────────┐
│        INPUT DATASETS            │    │      STAGING LAYER              │    │    INTERMEDIATE LAYER          │
│     (Pre-existing in Snowflake)  │    │   (Created by Airflow DAG)      │    │   (Created by Airflow DAG)      │
├─────────────────────────────────┤    ├─────────────────────────────────┤    ├─────────────────────────────────┤
│ • ORDERS (raw order data)        │───▶│ • stg_tpch_orders (View)         │───▶│ • int_order_items (Table)        │
│ • LINEITEM (raw line items)     │───▶│ • stg_tpch_line_items (View)    │───▶│ • int_order_items_summary (Table) │
└─────────────────────────────────┘    └─────────────────────────────────┘    └─────────────────────────────────┘
                                                                                        │
                                                                                        ▼
                                                                        ┌─────────────────────────────────┐
                                                                        │        MART LAYER                 │
                                                                        │   (Created by Airflow DAG)        │
                                                                        ├─────────────────────────────────┤
                                                                        │ • fct_orders (Table)             │
                                                                        │   ← stg_tpch_orders +              │
                                                                        │     int_order_items_summary        │
                                                                        └─────────────────────────────────┘
```

**Legend:**
- **Views**: Real-time data transformations (fast, always up-to-date)
- **Tables**: Materialized data for optimized querying (better performance)
- **←**: Shows data lineage (what each dataset is created from)

**Data Dependencies:**
1. **Raw Data** → **Staging Views** (cleaning & standardization)
2. **Staging Views** → **Intermediate Tables** (business logic & aggregations)
3. **Staging + Intermediate** → **Mart Tables** (final business-ready analytics)

Contact
=======

The Astronomer CLI is maintained with love by the Astronomer team. To report a bug or suggest a change, reach out to our support.
