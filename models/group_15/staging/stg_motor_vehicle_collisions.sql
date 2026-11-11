-- Staging model: NYC Motor Vehicle Collisions
-- Grain: one row = one collision (collision_id)
-- Cleans types, standardizes text, fills missing borough from zip, dedupes, filters to 2020 to 2025.

with source as (

    select * from {{ source('group_15_raw_data', 'source_motor_vehicle_collisions') }}

),

cleaned as (

    select
        cast(collision_id as string) as collision_id,

        -- date and time
        safe_cast(substr(cast(crash_date as string), 1, 10) as date) as crash_date,
        safe_cast(split(cast(crash_time as string), ':')[safe_offset(0)] as int64) as crash_hour,
        safe_cast(split(cast(crash_time as string), ':')[safe_offset(1)] as int64) as crash_minute,

        -- location
        nullif(upper(trim(cast(borough as string))), '') as borough,
        regexp_extract(cast(zip_code as string), r'^\d{5}') as zip_code,

        -- measures (null means 0)
        coalesce(safe_cast(number_of_persons_injured     as int64), 0) as number_of_persons_injured,
        coalesce(safe_cast(number_of_persons_killed      as int64), 0) as number_of_persons_killed,
        coalesce(safe_cast(number_of_pedestrians_injured as int64), 0) as number_of_pedestrians_injured,
        coalesce(safe_cast(number_of_pedestrians_killed  as int64), 0) as number_of_pedestrians_killed,
        coalesce(safe_cast(number_of_cyclist_injured     as int64), 0) as number_of_cyclist_injured,
        coalesce(safe_cast(number_of_cyclist_killed      as int64), 0) as number_of_cyclist_killed,
        coalesce(safe_cast(number_of_motorist_injured    as int64), 0) as number_of_motorist_injured,
        coalesce(safe_cast(number_of_motorist_killed     as int64), 0) as number_of_motorist_killed,

        -- vehicle types (1 to 5)
        nullif(upper(trim(vehicle_type_code1)), '')  as vehicle_type_1,
        nullif(upper(trim(vehicle_type_code2)), '')  as vehicle_type_2,
        nullif(upper(trim(vehicle_type_code_3)), '') as vehicle_type_3,
        nullif(upper(trim(vehicle_type_code_4)), '') as vehicle_type_4,
        nullif(upper(trim(vehicle_type_code_5)), '') as vehicle_type_5,

        -- contributing factors (1 to 5)
        nullif(upper(trim(contributing_factor_vehicle_1)), '') as contributing_factor_1,
        nullif(upper(trim(contributing_factor_vehicle_2)), '') as contributing_factor_2,
        nullif(upper(trim(contributing_factor_vehicle_3)), '') as contributing_factor_3,
        nullif(upper(trim(contributing_factor_vehicle_4)), '') as contributing_factor_4,
        nullif(upper(trim(contributing_factor_vehicle_5)), '') as contributing_factor_5

    from source
    where collision_id is not null

),

-- count collisions per zip and borough
zip_borough_counts as (

    select zip_code, borough, count(*) as n
    from cleaned
    where zip_code is not null and borough is not null
    group by zip_code, borough

),

-- most common borough for each zip, used to fill rows missing a borough
zip_borough_lookup as (

    select zip_code, borough
    from zip_borough_counts
    qualify row_number() over (partition by zip_code order by n desc) = 1

),

final as (

    select
        c.collision_id,
        c.crash_date,
        c.crash_hour,
        c.crash_minute,
        coalesce(c.borough, z.borough, 'UNKNOWN') as borough,
        case when c.borough is null and z.borough is not null then true else false end as is_borough_filled_from_zip,
        c.zip_code,
        c.number_of_persons_injured,
        c.number_of_persons_killed,
        c.number_of_pedestrians_injured,
        c.number_of_pedestrians_killed,
        c.number_of_cyclist_injured,
        c.number_of_cyclist_killed,
        c.number_of_motorist_injured,
        c.number_of_motorist_killed,
        c.vehicle_type_1,
        c.vehicle_type_2,
        c.vehicle_type_3,
        c.vehicle_type_4,
        c.vehicle_type_5,
        c.contributing_factor_1,
        c.contributing_factor_2,
        c.contributing_factor_3,
        c.contributing_factor_4,
        c.contributing_factor_5
    from cleaned c
    left join zip_borough_lookup z
        on c.zip_code = z.zip_code
    where c.crash_date between '2020-01-01' and '2025-12-31'
    qualify row_number() over (partition by c.collision_id order by c.crash_date) = 1

)

select * from final