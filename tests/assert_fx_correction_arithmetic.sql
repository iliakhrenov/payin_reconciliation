-- amount_usd_recon is the local amount at the rate published for the as-of date, on every row.
-- One rule, no carve-outs: the basis the whole reconciliation is priced against.
select
  txn_id,
  fx_variance_reason,
  amount_local,
  fx_rate_expected,
  amount_usd_engine,
  amount_usd_recon
from {{ ref('int__engine_log_fx_corrected') }}
where fx_rate_expected is not null
  and amount_usd_recon <> round(amount_local * fx_rate_expected, 2)
