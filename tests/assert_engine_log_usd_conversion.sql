-- amount_usd must be reproducible from the booked rate, or the engine's own math is unsound.
select
  txn_id,
  amount_local,
  fx_rate_applied,
  amount_usd,
  round(amount_local * fx_rate_applied, 2) as amount_usd_recomputed
from {{ ref('stg__payment_engine_log') }}
where amount_usd <> round(amount_local * fx_rate_applied, 2)
