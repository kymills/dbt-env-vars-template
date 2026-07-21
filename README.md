# dbt Environment Variables Template for dbt Projects on Snowflake

A template dbt project demonstrating the `env.yml` feature — SQL-powered environment
variables that replace `.env` files with a single Git-versioned config, giving each
engineer isolated schemas and dynamic data windows without an orchestrator.

## Prerequisites

| | |
|---|---|
| Snowflake Account | Any edition with dbt Projects on Snowflake enabled |
| Role | Must have CREATE TABLE, CREATE VIEW on the target schema |
| Warehouse | Any warehouse (XS is fine for development) |
| External Access Integration | Required for `dbt deps` to download packages from hub.getdbt.com |
| Git Repository | Fork this repo to your own GitHub account |

### External Access Integration Setup

Run once (requires ACCOUNTADMIN):

```sql
CREATE OR REPLACE NETWORK RULE dbt_network_rule
  MODE = EGRESS
  TYPE = HOST_PORT
  VALUE_LIST = ('hub.getdbt.com', 'codeload.github.com');

CREATE OR REPLACE EXTERNAL ACCESS INTEGRATION dbt_ext_access
  ALLOWED_NETWORK_RULES = (dbt_network_rule)
  ENABLED = TRUE;
```

## How It Works

```
┌─────────────────────────────────────────────────────────────────┐
│  EXECUTE DBT PROJECT ... ENVIRONMENT = 'prod'                    │
└─────────────────────┬───────────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────────┐
│  1. Snowflake resolves env.yml                                   │
│     - Picks the active environment (dev/staging/prod)            │
│     - Evaluates SQL: {{ select CURRENT_USER() }} → 'KMILLS'     │
│     - Injects values as environment variables                    │
└─────────────────────┬───────────────────────────────────────────┘
                      │
                      ▼
┌─────────────────────────────────────────────────────────────────┐
│  2. dbt starts                                                   │
│     - profiles.yml reads env_var('DBT_SCHEMA') → 'KMILLS'       │
│     - Models read env_var('DBT_DATA_INTERVAL_START')             │
│     - One config works for all environments                      │
└─────────────────────────────────────────────────────────────────┘
```

**Key benefits:**
- Per-developer schemas without manual config (`CURRENT_USER()` resolves at runtime)
- Dynamic data windows (yesterday, last 7 days, all-time) — no orchestrator needed
- One `profiles.yml` for all environments
- Git-versioned and auditable
- Secrets (Git tokens) are masked in logs automatically

## Project Structure

```
├── dbt_project.yml       # Project configuration
├── packages.yml          # Package dependencies
├── profiles.yml          # Reads env_var() — one file for all environments
├── env.yml               # ★ Environment variables (dev, staging, prod)
│
├── models/
│   ├── sources.yml       # Source table definitions — edit these first
│   ├── staging/
│   │   ├── stg_orders.sql
│   │   └── stg_customers.sql
│   └── marts/
│       └── daily_revenue_by_customer.sql  # Uses DBT_DATA_INTERVAL_*
│
├── macros/
├── seeds/
└── tests/
```

## Quick Start: Snowflake Workspace

1. Fork this repository to your GitHub account
2. Create a Workspace in Snowsight:
   - Navigate to **Projects > Workspaces**
   - Select **Create Workspace > From Git repository**
   - Enter your forked repo URL
3. Edit `env.yml` — replace `my_database` with your actual database name
4. Edit `models/sources.yml` — point to your actual source tables
5. Install dependencies — Select **Deps** from the command bar
6. Select your environment from the environment selector
7. **Build** — Select Build from the command bar

## Quick Start: Snowflake CLI

```bash
# Deploy
snow dbt deploy my_project --source . --dbt-version 1.11.11

# Run with dev environment (per-developer schema)
snow dbt execute my_project --env dev run

# Run with prod environment (yesterday's data)
snow dbt execute my_project --env prod run

# Override a variable for one run
snow dbt execute --env prod \
  --env-vars '{"DBT_DATA_INTERVAL_START": "2024-01-01 00:00:00"}' \
  my_project run
```

## Quick Start: SQL

```sql
-- Deploy from a Git stage
CREATE OR REPLACE DBT PROJECT my_db.my_schema.my_project
  FROM '@my_stage/branches/main'
  DEFAULT_ENVIRONMENT = 'dev'
  EXTERNAL_ACCESS_INTEGRATIONS = ('dbt_ext_access');

-- Run dev (each engineer gets schema = their username)
EXECUTE DBT PROJECT my_db.my_schema.my_project
  ENVIRONMENT = 'dev';

-- Run prod (yesterday's data window)
EXECUTE DBT PROJECT my_db.my_schema.my_project
  ARGS = 'build'
  ENVIRONMENT = 'prod';

-- Override variables for one execution
EXECUTE DBT PROJECT my_db.my_schema.my_project
  ENVIRONMENT = 'prod'
  ENV_VARS = ('DBT_DATA_INTERVAL_START' = '2024-06-01 00:00:00');
```

## Customization Guide

### 1. Edit `env.yml`

Replace placeholder values with your real database, warehouse, and role:

```yaml
env_config:
  default_environment: dev
  environments:
    - name: dev
      env:
        DBT_DATABASE: your_database          # ← Change this
        DBT_SCHEMA: "{{ select CURRENT_USER() }}"
        DBT_WAREHOUSE: your_dev_warehouse    # ← Change this
        DBT_ROLE: "{{ select CURRENT_ROLE() }}"
        DBT_DATA_INTERVAL_START: "2020-01-01 00:00:00"
        DBT_DATA_INTERVAL_END: "2099-12-31 23:59:59"
```

### 2. Edit `models/sources.yml`

Point to your real source tables:

```yaml
sources:
  - name: raw_data
    database: your_database    # ← Change this
    schema: raw                # ← Change this
    tables:
      - name: orders
      - name: customers
```

### 3. Use `env_var()` in your models

Filter on the dynamic data window:

```sql
select *
from {{ ref('stg_orders') }}
where order_date >= '{{ env_var("DBT_DATA_INTERVAL_START") }}'::timestamp
  and order_date <  '{{ env_var("DBT_DATA_INTERVAL_END") }}'::timestamp
```

### 4. Add private Git packages (optional)

Uncomment the `secrets:` block in `env.yml` and update `packages.yml`:

```yaml
# env.yml
secrets:
  - snowflake_secret: my_db.my_schema.my_git_token
    env_var_name: DBT_ENV_SECRET_GIT_TOKEN

# packages.yml
packages:
  - git: "https://{{env_var('DBT_ENV_SECRET_GIT_TOKEN')}}@github.com/my-org/my-repo.git"
    revision: main
```

## Scheduling with Snowflake Tasks

```sql
-- Nightly prod build at 6 AM
CREATE OR REPLACE TASK nightly_dbt_build
  WAREHOUSE = prod_wh
  SCHEDULE = 'USING CRON 0 6 * * * America/Denver'
AS
  EXECUTE DBT PROJECT my_db.my_schema.my_project
    ARGS = 'build'
    ENVIRONMENT = 'prod';

ALTER TASK nightly_dbt_build RESUME;
```

## Rules to Remember

| Rule | Example |
|------|---------|
| Keys must be `DBT_` prefixed | `DBT_SCHEMA`, not `SCHEMA` |
| Keys must be UPPERCASE | `DBT_DATABASE`, not `dbt_database` |
| SQL values need double quotes | `"{{ select CURRENT_USER() }}"` |
| Secrets must use `DBT_ENV_SECRET_` prefix | `DBT_ENV_SECRET_GIT_TOKEN` |
| `env.yml` lives next to `dbt_project.yml` | Project root |

## Precedence (highest wins)

| Priority | Source |
|----------|--------|
| 1 (highest) | `ENV_VARS = (...)` on EXECUTE / `--env-vars` on CLI |
| 2 | Shell env vars (CLI only, with `--use-shell-env-vars`) |
| 3 (lowest) | `env.yml` selected environment |

## Resources

- [Using SQL environment variables in dbt Projects on Snowflake](https://docs.snowflake.com/en/user-guide/data-engineering/dbt-projects-on-snowflake-environment-variables)
- [dbt Projects on Snowflake](https://docs.snowflake.com/en/user-guide/data-engineering/dbt-projects-on-snowflake)
- [EXECUTE DBT PROJECT](https://docs.snowflake.com/en/sql-reference/sql/execute-dbt-project)
- [CREATE DBT PROJECT](https://docs.snowflake.com/en/sql-reference/sql/create-dbt-project)
- [Snowflake CLI for dbt](https://docs.snowflake.com/en/developer-guide/snowflake-cli/dbt-commands)
