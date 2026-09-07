{% set export_path = var('export_dir') ~ '/recon_waterfall_' ~ var('reporting_month')[:7] ~ '.csv' %}

{{ config(
  post_hook = "copy (select * from {{ this }} order by psp, line_seq) to '" ~ export_path ~ "' (header, delimiter ',')"
) }}

-- The waterfall the CFO summary opens with, derived entirely from mart__recon_summary - the
-- three scope bases already are its levels. Nothing reads the classified layer, so anyone
-- holding only the summary CSV can rebuild this table.
--
-- Kept at psp grain: a total row would sit at a different grain and invite double-counting.
-- scripts/render_waterfall.py adds the Total column at render time.

with

summary as (
  select * from {{ ref('mart__recon_summary') }}
),

levels as (
  select
    reporting_month,
    psp,
    coalesce(max(base_usd) filter (where recon_scope = 'backend_fx'), 0) as backend_booked,
    coalesce(sum(signed_usd) filter (where recon_scope = 'backend_fx'), 0) as backend_fx_faults,
    coalesce(sum(signed_usd) filter (where recon_scope = 'gross'), 0) as provider_variance,
    coalesce(max(base_usd) filter (where recon_scope = 'gross'), 0) as provider_gross,
    coalesce(max(base_usd) filter (where recon_scope = 'fees'), 0) as provider_fees
  from summary
  group by 1, 2
),

lines as (
  select reporting_month, psp, 1 as line_seq, 'backend_booked' as line_item,
    backend_booked as usd, false as is_subtotal
  from levels

  union all
  select reporting_month, psp, 2, 'backend_fx_faults',
    backend_fx_faults, false
  from levels

  union all
  select reporting_month, psp, 3, 'backend_restated',
    backend_booked + backend_fx_faults, true
  from levels

  union all
  select reporting_month, psp, 4, 'provider_variance',
    provider_variance, false
  from levels

  union all
  select reporting_month, psp, 5, 'provider_gross',
    provider_gross, true
  from levels

  union all
  select reporting_month, psp, 6, 'provider_fees',
    -provider_fees, false
  from levels

  union all
  select reporting_month, psp, 7, 'net_receipts',
    provider_gross - provider_fees, true
  from levels
)

select
  reporting_month,
  psp,
  line_seq,
  line_item,
  cast(usd as decimal(18, 2)) as usd,
  is_subtotal
from lines
order by psp, line_seq
