select
    *
from {{ref('fct_orders')}}
where item_discount_amount > 0

-- test if there are neg discounts. Can't have a negative.
