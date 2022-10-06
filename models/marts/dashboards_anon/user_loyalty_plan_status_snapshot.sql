WITH user_statuses AS (
    SELECT *
    FROM {{ref('user_loyalty_plan_status')}}
)

,dim_date AS (
    SELECT *
    FROM {{ref('src__dim_date')}}
    WHERE
        DATE >= (SELECT MIN(STATUS_FROM_DATE) FROM user_statuses)
        AND DATE <= CURRENT_DATE()
)

,count_up AS (
    SELECT
        d.DATE
        ,u.BRAND
        ,u.LOYALTY_PLAN
        ,u.LOYALTY_PLAN_COMPANY
        ,COALESCE(SUM(CASE WHEN u.CURRENT_STATUS = 'ACTIVE' THEN 1 END),0) AS ACTIVE_STATE
        ,COALESCE(SUM(CASE WHEN u.CURRENT_STATUS = 'INACTIVE' OR u.CURRENT_STATUS = 'REGISTRATION' THEN 1 END),0) AS INACTIVE_STATE
        ,COALESCE(SUM(CASE WHEN u.CURRENT_STATUS = 'DORMANT' AND u.DAYS_SINCE_REGISTRATION >= 30 THEN 1 END),0) AS DORMANT_STATE
    FROM user_statuses u
    LEFT JOIN dim_date d
        ON d.DATE >= u.STATUS_FROM_DATE
        AND d.DATE < u.STATUS_TO_DATE
    GROUP BY
        d.DATE
        ,u.BRAND
        ,u.LOYALTY_PLAN
        ,u.LOYALTY_PLAN_COMPANY
    HAVING
        DATE IS NOT NULL
        AND
        (ACTIVE_STATE != 0
        OR INACTIVE_STATE != 0
        OR DORMANT_STATE != 0)
)

SELECT *
FROM count_up