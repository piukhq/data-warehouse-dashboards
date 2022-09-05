-- For the dashboard, 'join' refers to lc_join and lc_register events
-- This stages a union of these tables

WITH
lc_join AS (
    SELECT *
    FROM {{ref('src__fact_lc_join')}}
)

,lc_register AS (
    SELECT *
    FROM {{ref('src__fact_lc_register')}}
)

,all_lcs AS (
    SELECT
        EVENT_DATE_TIME
        ,EVENT_TYPE
        ,LOYALTY_CARD_ID
        ,LOYALTY_PLAN
        ,USER_ID
        ,'JOIN' AS ROUTE
    FROM
        lc_join
    UNION ALL
    SELECT
        EVENT_DATE_TIME
        ,EVENT_TYPE
        ,LOYALTY_CARD_ID
        ,LOYALTY_PLAN
        ,USER_ID
        ,'REGISTER' AS ROUTE
    FROM
        lc_register
)

SELECT *
FROM all_lcs
