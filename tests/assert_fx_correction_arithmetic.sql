select
  txn_id,
  fx_variance_reason,
  amount_usd_engine,
  amount_usd_recon
from {{ ref('int__engine_log_fx_corrected') }}
where
  case
    when fx_variance_reason in ('fx_not_applied', 'fx_rate_mismatch')
      then amount_usd_recon <> round(amount_local * fx_rate_published, 2)
    else amount_usd_recon <> amount_usd_engine
  end
