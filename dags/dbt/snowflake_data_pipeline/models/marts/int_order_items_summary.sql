select
    order_key,
    sum(extended_price) as gross_item_sales_amount,
    sum(item_discount) as item_discount_amount
from
    {{ ref('int_order_items') }}
group by
    order_key


-- dbt run -s int_order_items_summary
