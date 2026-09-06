with

src as (
  select * from {{ source('payin', 'fx_rates') }}
),

typed as (
  select
    cast(rate_date as date) as rate_date,
    currency,
    cast(usd_rate as decimal(18, 6)) as usd_rate,
    cast(published_at as timestamp) as published_at
  from src
),

versioned as (
  select
    *,
    row_number() over (
      partition by rate_date, currency
      order by published_at
    ) as rate_version,
    count(*) over (partition by rate_date, currency) as n_versions
  from typed
),

final as (
  select
    rate_date,
    currency,
    usd_rate,
    published_at,
    rate_version,
    rate_version = n_versions as is_current_rate
  from versioned
)

select * from final
