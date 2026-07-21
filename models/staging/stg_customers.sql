select
    customer_id,
    customer_name,
    segment,
    created_at
from {{ source('raw_data', 'customers') }}
where customer_id is not null
