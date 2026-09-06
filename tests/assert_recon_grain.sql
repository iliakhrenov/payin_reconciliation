-- The reconciliation spine is one row per provider transaction. Any fan-out is a broken join.
select
  psp,
  match_key,
  operation_type,
  count(*) as n_rows
from {{ ref('int__recon_matched') }}
group by 1, 2, 3
having count(*) > 1
