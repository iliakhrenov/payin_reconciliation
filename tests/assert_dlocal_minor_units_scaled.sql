-- local_amount is minor units and the exponent is per-currency, not a global divide by 100.
-- dLocal's own USD column, struck at its own inverted rate, is the independent check: a wrong
-- exponent is a 100x error and cannot hide inside the cent of rounding this allows.
select
  psp_reference,
  currency,
  amount_local,
  usd_amount_reported,
  fx_rate_local_per_usd
from (
  select
    staged.psp_reference,
    staged.currency,
    abs(staged.amount_local) as amount_local,
    cast(raw.usd_amount as decimal(18, 2)) as usd_amount_reported,
    cast(raw.fx_rate as decimal(18, 6)) as fx_rate_local_per_usd
  from {{ ref('stg__payment_log_dlocal') }} as staged
  join (select distinct * from {{ source('payin', 'dlocal_transactions') }}) as raw
    on raw.transaction_id = staged.psp_reference
   and (case raw.transaction_type when 'REFUND' then 'refund' else 'sale' end) = staged.operation_type
)
where abs(usd_amount_reported - round(amount_local / fx_rate_local_per_usd, 2)) > 0.01
