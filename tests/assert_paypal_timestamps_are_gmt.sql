-- PayPal declares GMT on every row and it verifies against the engine's captured_at_utc to the
-- second. No timezone conversion is applied. If a future export ships another zone, the amounts
-- would still tie while the period cut quietly moved, so the declaration is asserted, not read.
select
  "Time Zone" as declared_time_zone,
  count(*) as n_rows
from (
  select "Time Zone" from {{ source('payin', 'paypal_us_activity') }}
  union all
  select "Time Zone" from {{ source('payin', 'paypal_eu_activity') }}
)
where "Time Zone" <> 'GMT'
group by 1
