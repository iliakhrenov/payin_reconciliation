-- Per provider and scope: matched + explained + unexplained must equal an independently
-- recomputed control total. Catches a dropped row, a miscounted bucket or a flipped sign.
with

classified as (
  select * from {{ ref('int__recon_classified') }}
),

backend_fx as (
  select
    psp,
    'backend_fx' as recon_scope,
    sum(case when bug_status = 'matched' then bug_diff_usd else 0 end) as matched_usd,
    sum(case when bug_status = 'explained' then bug_diff_usd else 0 end) as explained_usd,
    sum(case when bug_status = 'unexplained' then bug_diff_usd else 0 end) as unexplained_usd,
    sum(engine_amount_usd_period) - sum(engine_amount_usd_booked_period) as control_usd
  from classified
  where engine_in_period
    and bug_cause is not null
  group by 1
),

gross as (
  select
    psp,
    'gross' as recon_scope,
    sum(case when gross_status = 'matched' then gross_diff_usd else 0 end) as matched_usd,
    sum(case when gross_status = 'explained' then gross_diff_usd else 0 end) as explained_usd,
    sum(case when gross_status = 'unexplained' then gross_diff_usd else 0 end) as unexplained_usd,
    sum(psp_amount_usd_period) + sum(psp_amount_usd_duplicate_period)
      - sum(engine_amount_usd_period) as control_usd
  from classified
  where in_period
  group by 1
),

fees as (
  select
    psp,
    'fees' as recon_scope,
    sum(case when net_status = 'matched' then net_diff_usd else 0 end) as matched_usd,
    sum(case when net_status = 'explained' then net_diff_usd else 0 end) as explained_usd,
    sum(case when net_status = 'unexplained' then net_diff_usd else 0 end) as unexplained_usd,
    sum(coalesce(fee_usd_contracted, 0)) - sum(coalesce(psp_fee_usd, 0)) as control_usd
  from classified
  where psp_in_period
    and net_cause is not null
  group by 1
),

buckets as (
  select * from backend_fx
  union all
  select * from gross
  union all
  select * from fees
)

select *
from buckets
where abs(matched_usd + explained_usd + unexplained_usd - control_usd) > 0.005
