-- The deliverable claims matched + explained + unexplained add up. A reader verifies that by
-- summing the CSV, so every provider and scope must carry an explicit unexplained row - an
-- absent one is indistinguishable from a bucket we forgot to compute.
select
  psp,
  recon_scope,
  count(*) as unexplained_rows
from {{ ref('mart__recon_summary') }}
group by 1, 2
having count(*) filter (where recon_status = 'unexplained') <> 1
