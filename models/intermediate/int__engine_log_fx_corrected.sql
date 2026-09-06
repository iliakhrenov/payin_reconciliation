with

engine as (
  select * from {{ ref('stg__payment_engine_log') }}
),

rates as (
  select
    rate_date,
    currency,
    usd_rate
  from {{ ref('stg__fx_rates') }}
  where is_current_rate
),

booked as (
  select
    engine.*,
    case
      when engine.currency = 'USD' then 1.0
      else rates.usd_rate
    end as fx_rate_published
  from engine
  left join rates
    on rates.rate_date = engine.fx_date_applied
   and rates.currency = engine.currency
),

expected as (
  select
    booked.*,
    (
      select max(rates.rate_date)
      from rates
      where rates.currency = booked.currency
        and rates.rate_date <= cast(booked.created_at_utc as date)
    ) as fx_date_expected
  from booked
),

classified as (
  select
    *,
    case
      when currency = 'USD' then 'none'
      when fx_rate_published is null then 'fx_rate_unpublished'
      when fx_rate_applied = 1 then 'fx_not_applied'
      when fx_rate_applied <> fx_rate_published then 'fx_rate_mismatch'
      when fx_date_applied <> fx_date_expected then 'fx_date_stale'
      else 'none'
    end as fx_variance_reason
  from expected
),

final as (
  select
    txn_id,
    order_id,
    operation_type,
    status,
    psp,
    psp_reference,
    sku,
    country,
    currency,
    amount_local,
    fx_rate_applied,
    fx_date_applied,
    fx_rate_published,
    fx_date_expected,
    fx_variance_reason,
    amount_usd as amount_usd_engine,
    case
      when fx_variance_reason in ('fx_not_applied', 'fx_rate_mismatch')
        then cast(round(amount_local * fx_rate_published, 2) as decimal(18, 2))
      else amount_usd
    end as amount_usd_recon,
    created_at_utc,
    captured_at_utc
  from classified
)

select
  *,
  amount_usd_engine - amount_usd_recon as fx_correction_usd
from final
