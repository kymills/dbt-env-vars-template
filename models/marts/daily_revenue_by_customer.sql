-- Uses DBT_DATA_INTERVAL_START / END from env.yml to filter the data window.
-- In dev: queries all history. In prod: queries yesterday only.
{{
    config(
        materialized='table',
        tags=['marts']
    )
}}

with orders as (
    select *
    from {{ ref('stg_orders') }}
    where order_date >= '{{ env_var("DBT_DATA_INTERVAL_START") }}'::timestamp
      and order_date <  '{{ env_var("DBT_DATA_INTERVAL_END") }}'::timestamp
),

customers as (
    select * from {{ ref('stg_customers') }}
)

select
    c.customer_name,
    c.segment,
    date_trunc('day', o.order_date) as order_day,
    count(o.order_id) as total_orders,
    sum(o.total_amount) as total_revenue,
    current_timestamp() as refreshed_at
from orders o
inner join customers c on o.customer_id = c.customer_id
group by 1, 2, 3
