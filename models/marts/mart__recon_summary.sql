with

classified as (
  select * from {{ ref('int__recon_classified') }}
),

lines as (
  select
    psp,
    'engine_bugs' as recon_scope,
    bug_status as recon_status,
    bug_cause as recon_cause,
    bug_diff_usd as diff_usd
  from classified
  where engine_in_period
    and bug_cause is not null

  union all

  select
    psp,
    'gross' as recon_scope,
    gross_status,
    gross_cause,
    gross_diff_usd
  from classified
  where in_period

  union all

  select
    psp,
    'net' as recon_scope,
    net_status,
    net_cause,
    net_diff_usd
  from classified
  where psp_in_period
    and net_cause is not null
),

by_cause as (
  select
    psp,
    recon_scope,
    recon_status,
    recon_cause,
    count(*) as n_rows,
    sum(abs(diff_usd)) as abs_usd,
    sum(diff_usd) as signed_usd
  from lines
  group by 1, 2, 3, 4
),

final as (
  select
    psp,
    recon_scope,
    recon_status,
    recon_cause,
    n_rows,
    cast(abs_usd as decimal(18, 2)) as abs_usd,
    cast(signed_usd as decimal(18, 2)) as signed_usd,
    cast(
      round(100.0 * abs_usd / nullif(sum(abs_usd) over (partition by psp, recon_scope), 0), 2)
      as decimal(6, 2)
    ) as pct_of_discrepancy
  from by_cause
)

select * from final
order by psp, recon_scope, recon_status, abs_usd desc
