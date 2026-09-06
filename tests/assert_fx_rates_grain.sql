select
  rate_date,
  currency,
  rate_version,
  count(*) as n
from {{ ref('stg__fx_rates') }}
group by 1, 2, 3
having count(*) > 1
