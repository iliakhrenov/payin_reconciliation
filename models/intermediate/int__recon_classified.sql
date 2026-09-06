{% set period = "date '" ~ var('reporting_month') ~ "'" %}

with

matched as (
  select * from {{ ref('int__recon_matched') }}
),

scoped as (
  select
    *,
    engine_period = {{ period }} as engine_in_period,
    psp_period = {{ period }} as psp_in_period,
    case when engine_period = {{ period }} then coalesce(engine_amount_usd_settled, 0) else 0 end
      as engine_amount_usd_period,
    case when engine_period = {{ period }} then coalesce(engine_amount_usd_booked, 0) else 0 end
      as engine_amount_usd_booked_period,
    case when psp_period = {{ period }} then coalesce(psp_amount_usd_settled, 0) else 0 end
      as psp_amount_usd_period
  from matched
),

classified as (
  select
    *,
    psp_amount_usd_period - engine_amount_usd_period as gross_diff_usd,
    engine_amount_usd_period - engine_amount_usd_booked_period as bug_diff_usd,
    case when psp_in_period then coalesce(fee_usd_contracted - psp_fee_usd, 0) else 0 end as net_diff_usd,
    case
      when not in_engine then null
      when engine_fx_variance_reason = 'none' then 'matched'
      else 'engine_' || engine_fx_variance_reason
    end as bug_cause,
    case
      when fee_local_contracted is not null and psp_fee_local > fee_local_contracted then 'psp_fee_overcharge'
      when fee_local_contracted is not null and psp_fee_local < fee_local_contracted then 'psp_fee_undercharge'
      when fee_local_contracted is not null then 'matched'
      when in_psp and operation_type = 'sale' and psp_status = 'settled' then 'fee_not_contracted'
    end as net_cause,
    case
      when not in_engine and operation_type = 'chargeback' then 'psp_claims_chargeback'
      when not in_engine and operation_type = 'sale' then 'psp_claims_sale'
      when engine_status = 'settled' and psp_status = 'declined' then 'psp_claims_declined'
      when psp_amount_local_authorised is not null
        and psp_amount_local_settled <> psp_amount_local_authorised
        and engine_amount_local_settled = psp_amount_local_authorised then 'psp_claims_partial_capture'
      when engine_period is distinct from psp_period then 'psp_claims_captured_different_period'
      when psp_amount_usd_period - engine_amount_usd_period = 0 then 'matched'
      else 'unexplained'
    end as gross_cause
  from scoped
),

final as (
  select
    *,
    case gross_cause
      when 'matched' then 'matched'
      when 'unexplained' then 'unexplained'
      else 'explained'
    end as gross_status,
    case net_cause
      when 'matched' then 'matched'
      when 'unexplained' then 'unexplained'
      else 'explained'
    end as net_status,
    case bug_cause
      when 'matched' then 'matched'
      when 'unexplained' then 'unexplained'
      else 'explained'
    end as bug_status,
    engine_in_period or psp_in_period as in_period
  from classified
)

select * from final
