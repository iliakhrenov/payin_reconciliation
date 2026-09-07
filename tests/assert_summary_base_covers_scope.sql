-- Materiality is only readable if the base is the whole book, never smaller than the breaks it
-- is meant to put in proportion. A base below its own scope's absolute discrepancy would make
-- pct_of_base exceed 100 and read as a broken rate rather than a real one.
select
  psp,
  recon_scope,
  max(base_usd) as base_usd,
  sum(abs_usd) as scope_abs_usd
from {{ ref('mart__recon_summary') }}
group by 1, 2
having sum(abs_usd) > max(base_usd) + 0.005
