-- A fee classified as matched must carry no dollars. The variance is a local-currency fact,
-- so it is priced from the local difference: converting each side separately and subtracting
-- leaves a cent of rounding on rows where the provider derives its own USD fee differently
-- (Google Play takes 15% of the USD gross, not 15% of the local fee converted).
select *
from {{ ref('int__recon_classified') }}
where net_cause = 'matched'
  and net_diff_usd <> 0
