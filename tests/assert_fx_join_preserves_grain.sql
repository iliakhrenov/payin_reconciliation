-- fx_rates carries republished rates; a join that missed that would fan rows out silently.
select
  (select count(*) from {{ ref('stg__payment_engine_log') }}) as n_staging,
  (select count(*) from {{ ref('int__engine_log_fx_corrected') }}) as n_intermediate
where
  (select count(*) from {{ ref('stg__payment_engine_log') }})
  <> (select count(*) from {{ ref('int__engine_log_fx_corrected') }})
