{% set export_path = var('export_dir') ~ '/recon_summary_' ~ var('reporting_month')[:7] ~ '.csv' %}

{{ config(
  post_hook = "copy (select * from {{ this }} order by psp, recon_scope, abs_usd desc, recon_cause) to '" ~ export_path ~ "' (header, delimiter ',')"
) }}

with

classified as (
  select * from {{ ref('int__recon_classified') }}
),

lines as (
  select
    psp,
    'backend_fx' as recon_scope,
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
    'fees' as recon_scope,
    net_status,
    net_cause,
    net_diff_usd
  from classified
  where psp_in_period
    and net_cause is not null
),

-- The denominator materiality is judged against. Deliberately the provider's whole book for
-- the scope, not just the rows that broke: a fee variance means nothing until you know the
-- fee bill it sits in.
bases as (
  select
    psp,
    'backend_fx' as recon_scope,
    'backend booked gross' as base_label,
    sum(engine_amount_usd_booked_period) as base_usd
  from classified
  where in_period
  group by 1

  union all

  select
    psp,
    'gross' as recon_scope,
    'provider gross' as base_label,
    sum(psp_amount_usd_period) + sum(psp_amount_usd_duplicate_period) as base_usd
  from classified
  where in_period
  group by 1

  union all

  select
    psp,
    'fees' as recon_scope,
    'provider fees charged' as base_label,
    sum(coalesce(psp_fee_usd, 0)) as base_usd
  from classified
  where psp_in_period
  group by 1
),

by_cause as (
  select
    psp,
    recon_scope,
    recon_status,
    recon_cause,
    cast(count(*) as bigint) as n_rows,
    cast(sum(abs(diff_usd)) as decimal(38, 2)) as abs_usd,
    cast(sum(diff_usd) as decimal(38, 2)) as signed_usd
  from lines
  group by 1, 2, 3, 4
),

-- A residual of zero has to be stated, not implied by an absent row - the deliverable claims
-- matched + explained + unexplained add up, and a reader cannot verify that against a gap.
residual_stated as (
  select
    s.psp,
    s.recon_scope,
    'unexplained' as recon_status,
    'unexplained' as recon_cause,
    cast(0 as bigint) as n_rows,
    cast(0 as decimal(38, 2)) as abs_usd,
    cast(0 as decimal(38, 2)) as signed_usd
  from (select distinct psp, recon_scope from lines) s
  left join by_cause c
    on c.psp = s.psp
    and c.recon_scope = s.recon_scope
    and c.recon_status = 'unexplained'
  where c.psp is null
),

all_causes as (
  select * from by_cause
  union all
  select * from residual_stated
),

final as (
  select
    cast('{{ var("reporting_month") }}' as date) as reporting_month,
    c.psp,
    c.recon_scope,
    c.recon_status,
    c.recon_cause,
    c.n_rows,
    cast(c.abs_usd as decimal(18, 2)) as abs_usd,
    cast(c.signed_usd as decimal(18, 2)) as signed_usd,
    b.base_label,
    cast(b.base_usd as decimal(18, 2)) as base_usd,
    cast(
      coalesce(round(100.0 * c.abs_usd / nullif(b.base_usd, 0), 4), 0)
      as decimal(12, 4)
    ) as pct_of_base,
    cast(
      coalesce(
        round(
          100.0 * c.abs_usd
            / nullif(sum(c.abs_usd) over (partition by c.psp, c.recon_scope), 0),
          2
        ),
        0
      ) as decimal(6, 2)
    ) as pct_of_scope_discrepancy,
    cast(
      coalesce(round(100.0 * c.abs_usd / nullif(sum(c.abs_usd) over (), 0), 2), 0)
      as decimal(6, 2)
    ) as pct_of_total_discrepancy
  from all_causes c
  left join bases b
    on b.psp = c.psp
    and b.recon_scope = c.recon_scope
)

select * from final
order by psp, recon_scope, abs_usd desc, recon_cause
