-- Clean and standardize DOB NOW job filing data
-- One row per job filing

WITH source AS (
   SELECT * FROM {{ source('raw', 'source_nyc_dob_job_apps') }}
),

cleaned AS (
   SELECT
       * EXCEPT (
           job_filing_number,
           filing_status,
           job_type,
           filing_date,
           current_status_date,
           first_permit_date,
           approved_date,
           signoff_date,
           borough,
           postcode,
           zip,
           council_district,
           latitude,
           longitude,
           filing_representative_zip
       ),

       -- Identifiers
       CAST(job_filing_number AS STRING) AS job_filing_number,

       -- Filing details
       UPPER(TRIM(filing_status)) AS filing_status,
       UPPER(TRIM(job_type)) AS job_type,

       -- Dates (names must match what dim_date expects)
       SAFE_CAST(filing_date AS TIMESTAMP) AS filing_date,
       SAFE_CAST(current_status_date AS TIMESTAMP) AS current_status_date,
       SAFE_CAST(first_permit_date AS TIMESTAMP) AS first_permit_date,
       SAFE_CAST(approved_date AS TIMESTAMP) AS approved_date,
       SAFE_CAST(signoff_date AS TIMESTAMP) AS signoff_date,

       -- Location: conformed names to match 311 staging
       CASE
           WHEN UPPER(TRIM(borough)) IN ('MANHATTAN', 'NEW YORK COUNTY') THEN 'Manhattan'
           WHEN UPPER(TRIM(borough)) IN ('BRONX', 'THE BRONX') THEN 'Bronx'
           WHEN UPPER(TRIM(borough)) IN ('BROOKLYN', 'KINGS COUNTY') THEN 'Brooklyn'
           WHEN UPPER(TRIM(borough)) IN ('QUEENS', 'QUEEN', 'QUEENS COUNTY') THEN 'Queens'
           WHEN UPPER(TRIM(borough)) IN ('STATEN ISLAND', 'RICHMOND COUNTY') THEN 'Staten Island'
           ELSE 'UNKNOWN or CITYWIDE'
       END AS borough,

       -- Job site zip (postcode) becomes the conformed zip
       CASE
           WHEN LENGTH(TRIM(postcode)) = 5 THEN TRIM(postcode)
           WHEN REGEXP_CONTAINS(postcode, r'^\d{5}-\d{4}$') THEN postcode
           ELSE NULL
       END AS zip,

       -- Owner's mailing zip, renamed so it doesn't clash
       zip AS owner_zip,

       CAST(council_district AS STRING) AS council_district,
       SAFE_CAST(latitude AS NUMERIC) AS latitude,
       SAFE_CAST(longitude AS NUMERIC) AS longitude,

       -- Filing rep zip kept as string for dim_filing_representative
       filing_representative_zip,

       -- Metadata
       CURRENT_TIMESTAMP() AS _stg_loaded_at

   FROM source

   -- Filters
   WHERE job_filing_number IS NOT NULL
     AND filing_date IS NOT NULL
     AND borough IS NOT NULL

   -- Deduplicate: keep most recent status per filing
   QUALIFY ROW_NUMBER() OVER (
       PARTITION BY job_filing_number
       ORDER BY current_status_date DESC
   ) = 1
)

SELECT * FROM cleaned