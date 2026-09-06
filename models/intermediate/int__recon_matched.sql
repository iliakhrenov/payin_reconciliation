with

psp as (
  select * from {{ ref('int__psp_transactions') }}
),

engine as (
  select
    txn_id,
    order_id,
    psp,
    psp_reference,
    lower(operation_type) as operation_type,
    status,
    sku,
    country,
    currency,
    case
      when lower(operation_type) = 'sale' then amount_local
      else -amount_local
    end as amount_local,
    case
      when status <> 'settled' then cast(0 as decimal(18, 2))
      when lower(operation_type) = 'sale' then amount_local
      else -amount_local
    end as amount_local_settled,
    case
      when status <> 'settled' then cast(0 as decimal(18, 2))
      when lower(operation_type) = 'sale' then amount_usd_recon
      else -amount_usd_recon
    end as amount_usd_settled,
    case
      when status <> 'settled' then cast(0 as decimal(18, 2))
      when lower(operation_type) = 'sale' then amount_usd_engine
      else -amount_usd_engine
    end as amount_usd_booked,
    fx_variance_reason,
    fx_correction_usd,
    created_at_utc,
    captured_at_utc,
    coalesce(captured_at_utc, created_at_utc) as recognised_at_utc
  from {{ ref('int__engine_log_fx_corrected') }}
  where psp in (select distinct psp from psp)
),

joined as (
  select
    coalesce(engine.psp, psp.psp) as psp,
    coalesce(engine.order_id, psp.order_ref) as order_ref,
    coalesce(engine.operation_type, psp.operation_type) as operation_type,

    engine.txn_id,
    engine.status as engine_status,
    engine.currency as engine_currency,
    engine.amount_local as engine_amount_local,
    engine.amount_local_settled as engine_amount_local_settled,
    engine.amount_usd_settled as engine_amount_usd_settled,
    engine.amount_usd_booked as engine_amount_usd_booked,
    engine.fx_variance_reason as engine_fx_variance_reason,
    engine.fx_correction_usd as engine_fx_correction_usd,
    engine.recognised_at_utc as engine_recognised_at_utc,
    engine.sku,
    engine.country,

    psp.psp_account,
    psp.psp_reference,
    psp.status as psp_status,
    psp.currency as psp_currency,
    psp.amount_local as psp_amount_local,
    psp.amount_local_settled as psp_amount_local_settled,
    psp.amount_local_authorised as psp_amount_local_authorised,
    psp.amount_usd_settled as psp_amount_usd_settled,
    psp.amount_local_duplicate as psp_amount_local_duplicate,
    psp.amount_usd_duplicate as psp_amount_usd_duplicate,
    psp.fee_local as psp_fee_local,
    psp.fee_usd as psp_fee_usd,
    psp.fee_local_contracted,
    psp.fee_usd_contracted,
    psp.percent_fee,
    psp.fixed_fee,
    psp.fixed_fee_currency,
    psp.fx_rate_recon as psp_fx_rate_recon,
    psp.recognised_at_utc as psp_recognised_at_utc,
    psp.batch_number,

    engine.txn_id is not null as in_engine,
    psp.order_ref is not null as in_psp
  from engine
  full outer join psp
    on psp.psp = engine.psp
   and psp.order_ref = engine.order_id
   and psp.operation_type = engine.operation_type
),

final as (
  select
    *,
    coalesce(psp_amount_local_settled, 0) - coalesce(engine_amount_local_settled, 0) as diff_local,
    coalesce(psp_amount_usd_settled, 0) - coalesce(engine_amount_usd_settled, 0) as diff_usd,
    date_trunc('month', engine_recognised_at_utc) as engine_period,
    date_trunc('month', psp_recognised_at_utc) as psp_period
  from joined
)

select * from final
