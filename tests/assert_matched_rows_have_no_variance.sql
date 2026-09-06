-- A row classified as matched must agree on status, currency and amount. Nothing hides in the bucket.
select *
from {{ ref('int__recon_classified') }}
where gross_cause = 'matched'
  and (
    not (in_engine and in_psp)
    or engine_status <> psp_status
    or engine_currency <> psp_currency
    or diff_local <> 0
    or diff_usd <> 0
  )
