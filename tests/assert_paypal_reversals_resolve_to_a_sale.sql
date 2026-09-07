-- Every PayPal reversal carries a Reference Txn ID pointing at the sale it reverses. It is not
-- the join key, but if one stops resolving - or points at another account, another order, or a
-- transaction that never settled - the refund is not what the file says it is.
with

paypal as (
  select * from {{ ref('stg__payment_log_paypal') }}
),

reversals as (
  select * from paypal where operation_type in ('refund', 'chargeback')
)

select
  reversals.psp,
  reversals.order_ref,
  reversals.psp_reference,
  reversals.related_psp_reference
from reversals
left join paypal as sale
  on sale.psp = reversals.psp
 and sale.psp_reference = reversals.related_psp_reference
where reversals.related_psp_reference is null
   or sale.psp_reference is null
   or sale.operation_type <> 'sale'
   or sale.status <> 'settled'
   or sale.order_ref <> reversals.order_ref
   or abs(reversals.amount_local) > sale.amount_local
   or reversals.created_at_utc < sale.created_at_utc
