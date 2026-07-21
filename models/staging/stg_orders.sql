select
    order_id,
    customer_id,
    order_date,
    total_amount
from {{ source('raw_data', 'orders') }}
where order_date is not null
