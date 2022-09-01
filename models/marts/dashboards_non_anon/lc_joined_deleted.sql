WITH mock_brands AS (
    SELECT *
    FROM {{ref('mock_brands')}}
)

,lc_join AS (
    SELECT *
    FROM {{ref('src__fact_lc_join')}}
)

,lc_removed AS (
    SELECT *
    FROM {{ref('src__fact_lc_removed')}}
)

,dim_lc AS (
    SELECT *
    FROM {{ref('src__dim_loyalty_card')}}
)

,dim_date AS (
    SELECT *
    FROM {{ref('src__dim_date')}}
)

,lc_start_end as (
    SELECT
        lcj.LOYALTY_CARD_ID
        ,DATE(lcj.EVENT_DATE_TIME) AS START_DATE
        ,DATE(lcr.EVENT_DATE_TIME) AS END_DATE
        ,b.BRAND
        ,dlc.LOYALTY_PLAN_COMPANY
    FROM lc_join lcj
    LEFT JOIN lc_removed lcr
        ON lcj.LOYALTY_CARD_ID  = lcr.LOYALTY_CARD_ID
    LEFT JOIN mock_brands b
        ON lcj.USER_ID = b.USER_ID
    LEFT JOIN dim_lc dlc
        ON dlc.LOYALTY_CARD_ID = lcj.LOYALTY_CARD_ID
    WHERE
        EVENT_TYPE = 'SUCCESS'
)
      
,lc_creations as (
    SELECT
        START_DATE
        ,BRAND
        ,LOYALTY_PLAN_COMPANY
        ,COUNT(*) c
    FROM
        lc_start_end
    GROUP BY
        START_DATE
        ,BRAND
        ,LOYALTY_PLAN_COMPANY
)

,lc_deletions as (
    SELECT
        END_DATE
        ,BRAND
        ,LOYALTY_PLAN_COMPANY
        ,COUNT(*) c
    FROM
        lc_start_end
    WHERE
        END_DATE IS NOT NULL
    GROUP BY
        END_DATE
        ,BRAND
        ,LOYALTY_PLAN_COMPANY
)
  
,date_range AS (
    SELECT
        DATE
    FROM
        dim_date
    WHERE
        DATE >= (SELECT MIN(START_DATE) FROM LC_START_END)
        AND DATE <= CURRENT_DATE()
)
  
,union_matching_records AS (
    SELECT
        START_DATE AS DATE
        ,BRAND
        ,LOYALTY_PLAN_COMPANY
    FROM lc_creations
    UNION
    SELECT
        END_DATE AS DATE
        ,BRAND
        ,LOYALTY_PLAN_COMPANY
    FROM lc_deletions
) 

,count_up as (
    SELECT
        d.DATE
        ,r.BRAND
        ,r.LOYALTY_PLAN_COMPANY
        ,lcc.C AS LC_CREATED
        ,COALESCE(lcd.C,0) AS LC_DELETED
        ,LC_CREATED - LC_DELETED AS DAILY_CHANGE_IN_LC
        ,SUM(DAILY_CHANGE_IN_LC) OVER (PARTITION BY r.BRAND, r.LOYALTY_PLAN_COMPANY ORDER BY d.DATE ASC) AS TOTAL_LC_COUNT
    FROM date_range d
    LEFT JOIN union_matching_records r
        ON d.DATE = r.DATE
    LEFT JOIN lc_creations lcc
        ON d.DATE = lcc.START_DATE
            AND r.BRAND = lcc.BRAND
            AND r.LOYALTY_PLAN_COMPANY = lcc.LOYALTY_PLAN_COMPANY
    LEFT JOIN lc_deletions lcd
        ON d.DATE = lcd.END_DATE
            AND r.BRAND = lcd.BRAND
            AND r.LOYALTY_PLAN_COMPANY = lcd.LOYALTY_PLAN_COMPANY
)

SELECT *
FROM count_up
ORDER BY
    DATE
    ,BRAND
    ,LOYALTY_PLAN_COMPANY
