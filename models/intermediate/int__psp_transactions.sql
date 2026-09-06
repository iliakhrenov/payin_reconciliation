with

providers as (
  select * from {{ ref('stg__payment_log_adyen') }}
  union all by name
  select * from {{ ref('stg__payment_log_dlocal') }}
),

contracts as (
  select * from {{ ref('stg__fee_schedule') }}
),

rates as (
  select
    rate_date,
    currency,
    usd_rate
  from {{ ref('stg__fx_rates') }}
  where is_current_rate
),

priced as (
  select
    providers.*,
    case
      when providers.currency = 'USD' then cast(1.0 as decimal(18, 6))
      else (
        select rates.usd_rate
        from rates
        where rates.currency = providers.currency
          and rates.rate_date <= cast(providers.created_at_utc as date)
        order by rates.rate_date desc
        limit 1
      )
    end as fx_rate_recon
  from providers
),

contracted as (
  select
    priced.*,
    contract.percent_fee,
    contract.fixed_fee,
    contract.fixed_fee_currency,
    case
      when priced.operation_type <> 'sale' or priced.status <> 'settled' then null
      when contract.percent_fee is null then null
      else cast(
        round(priced.amount_local_settled * contract.percent_fee / 100, 2)
        + case
            when contract.fixed_fee_currency is null or contract.fixed_fee_currency = priced.currency
              then contract.fixed_fee
            else 0
          end
        as decimal(18, 2)
      )
    end as fee_local_contracted
  from priced
  left join lateral (
    select
      contracts.percent_fee,
      contracts.fixed_fee,
      contracts.fixed_fee_currency
    from contracts
    where contracts.psp = priced.psp
      and contracts.psp_account = priced.psp_account
      and contracts.valid_from <= cast(coalesce(priced.settled_at_utc, priced.created_at_utc) as date)
    order by contracts.valid_from desc
    limit 1
  ) as contract on true
),

final as (
  select
    psp,
    psp_account,
    psp_reference,
    order_ref,
    operation_type,
    status,
    currency,
    amount_local,
    amount_local_settled,
    amount_local_authorised,
    amount_local_duplicate,
    fee_commission_local,
    fee_markup_local,
    fee_local,
    fee_usd_native,
    net_local,
    percent_fee,
    fixed_fee,
    fixed_fee_currency,
    fee_local_contracted,
    fx_rate_recon,
    cast(round(amount_local * fx_rate_recon, 2) as decimal(18, 2)) as amount_usd,
    cast(round(amount_local_settled * fx_rate_recon, 2) as decimal(18, 2)) as amount_usd_settled,
    cast(round(amount_local_duplicate * fx_rate_recon, 2) as decimal(18, 2)) as amount_usd_duplicate,
    coalesce(
      fee_usd_native,
      cast(round(fee_local * fx_rate_recon, 2) as decimal(18, 2))
    ) as fee_usd,
    cast(round(fee_local_contracted * fx_rate_recon, 2) as decimal(18, 2)) as fee_usd_contracted,
    created_at_utc,
    settled_at_utc,
    coalesce(settled_at_utc, created_at_utc) as recognised_at_utc,
    batch_number
  from contracted
)

select * from final
