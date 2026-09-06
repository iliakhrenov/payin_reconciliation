-- The report's central claim: what the backend booked, plus its own bugs, plus the provider
-- variance, is what the provider says it took. If this drifts the three sections stop being
-- one story about the same money.
with

totals as (
  select
    psp,
    sum(engine_amount_usd_booked_period) as booked_usd,
    sum(bug_diff_usd) as bugs_usd,
    sum(gross_diff_usd) as gross_usd,
    sum(psp_amount_usd_period) as psp_usd
  from {{ ref('int__recon_classified') }}
  where in_period
  group by 1
)

select *
from totals
where abs(booked_usd + bugs_usd + gross_usd - psp_usd) > 0.005
