/*
Created by:         Anand Bhakta
Created date:       2023-02-05
Last modified by:   
Last modified date: 

Description:
    Rewrite of the LL table lc_joins_links_snapshot and lc_joins_links containing both snapshot and daily absolute data of all link and join journeys split by merchant.
Notes:
    This code can be made more efficient if the start is pushed to the trans__lbg_user code and that can be the source for the majority of the dashboards including user_loyalty_plan_snapshot and user_with_loyalty_cards
Parameters:
    source_object       - src__fact_lc_add
                        - src__fact_lc_removed
                        - src__dim_loyalty_card
                        - src__dim_date
*/

WITH lc_events AS (
    SELECT *
    FROM {{ref('src__fact_lc_add')}}
    WHERE CHANNEL = 'LLOYDS'
)

,lc_removed AS (
    SELECT *
    FROM {{ref('src__fact_lc_removed')}}
        WHERE CHANNEL = 'LLOYDS'
)

,dim_lc AS (
    SELECT *
    FROM {{ref('src__dim_loyalty_card')}}
)

,dim_date AS (
    SELECT *
    FROM {{ref('src__dim_date')}}
    WHERE
        DATE >= (SELECT MIN(DATE(EVENT_DATE_TIME)) FROM lc_events)
        AND DATE <= CURRENT_DATE()
)

,adding_deletes AS (
    SELECT
        EVENT_DATE_TIME
        ,USER_ID
        ,BRAND
        ,EXTERNAL_USER_REF
        ,LOYALTY_CARD_ID
        ,EVENT_TYPE
        ,AUTH_TYPE
    FROM
        lc_events
    UNION
    SELECT
        EVENT_DATE_TIME
        ,USER_ID
        ,BRAND
        ,EXTERNAL_USER_REF
        ,LOYALTY_CARD_ID
        ,'DELETE' AS EVENT_TYPE
        ,NULL AS AUTH_TYPE
    FROM
        lc_removed
)

,transforming_deletes AS (
    SELECT
        EVENT_DATE_TIME
        ,USER_ID
        ,BRAND
        ,EXTERNAL_USER_REF
        ,LOYALTY_CARD_ID
        ,EVENT_TYPE
        ,LAG(AUTH_TYPE, 1) OVER (PARTITION BY EXTERNAL_USER_REF, LOYALTY_CARD_ID ORDER BY EVENT_DATE_TIME ASC) AS AUTH_TYPE
        ,LAG(EVENT_TYPE, 1) OVER (PARTITION BY EXTERNAL_USER_REF, LOYALTY_CARD_ID ORDER BY EVENT_DATE_TIME ASC) AS PREV_EVENT
    FROM adding_deletes
    QUALIFY
        EVENT_TYPE = 'DELETE'
        AND
        PREV_EVENT = 'SUCCESS'
)

,combine AS (
    SELECT
        EVENT_DATE_TIME
        ,USER_ID
        ,BRAND
        ,EXTERNAL_USER_REF
        ,LOYALTY_CARD_ID
        ,AUTH_TYPE
        ,EVENT_TYPE
    FROM transforming_deletes
    UNION
    SELECT
        EVENT_DATE_TIME
        ,USER_ID
        ,BRAND
        ,EXTERNAL_USER_REF
        ,LOYALTY_CARD_ID
        ,AUTH_TYPE
        ,EVENT_TYPE
    FROM lc_events
    
)

,to_from_dates AS (
    SELECT
        l.USER_ID
        ,l.BRAND
        ,l.EXTERNAL_USER_REF
        ,l.loyalty_card_id
        ,COALESCE(
            CASE WHEN l.auth_type IN ('ADD AUTH', 'AUTH') THEN 'LINK' END,
            CASE WHEN l.auth_type IN ('JOIN', 'REGISTER') THEN 'JOIN' END
                ) AS ADD_JOURNEY
        ,l.event_type
        ,d.LOYALTY_PLAN_NAME
        ,d.LOYALTY_PLAN_COMPANY
        ,l.EVENT_TYPE AS FROM_EVENT
        ,DATE(l.EVENT_DATE_TIME) AS FROM_DATE
        ,DATE(LEAD(l.EVENT_DATE_TIME, 1) OVER (PARTITION BY l.EXTERNAL_USER_REF, d.LOYALTY_PLAN_NAME ORDER BY EVENT_DATE_TIME)) AS TO_DATE
        ,LEAD(l.EVENT_TYPE, 1) OVER (PARTITION BY l.EXTERNAL_USER_REF, d.LOYALTY_PLAN_NAME ORDER BY l.EVENT_DATE_TIME) AS TO_EVENT
    FROM
    combine l
    LEFT JOIN dim_lc d 
        ON l.loyalty_card_id = d.loyalty_card_id
)
        
,count_up_snap AS (
  SELECT
    d.DATE
    ,u.BRAND
    ,u.LOYALTY_PLAN_NAME
    ,u.LOYALTY_PLAN_COMPANY
        ,COALESCE(SUM(CASE WHEN EVENT_TYPE = 'SUCCESS' AND ADD_JOURNEY = 'JOIN' THEN 1 END),0) AS JOIN_SUCCESS_STATE
        ,COALESCE(SUM(CASE WHEN EVENT_TYPE = 'FAILED' AND ADD_JOURNEY = 'JOIN' THEN 1 END),0) AS JOIN_FAILED_STATE
        ,COALESCE(SUM(CASE WHEN EVENT_TYPE = 'REQUEST' AND ADD_JOURNEY = 'JOIN' THEN 1 END),0) AS JOIN_PENDING_STATE
        ,COALESCE(SUM(CASE WHEN EVENT_TYPE = 'DELETE' AND ADD_JOURNEY = 'JOIN' THEN 1 END),0) AS JOIN_REMOVED_STATE
  
        ,COALESCE(SUM(CASE WHEN EVENT_TYPE = 'SUCCESS' AND ADD_JOURNEY = 'LINK' THEN 1 END),0) AS LINK_SUCCESS_STATE
        ,COALESCE(SUM(CASE WHEN EVENT_TYPE = 'FAILED' AND ADD_JOURNEY = 'LINK' THEN 1 END),0) AS LINK_FAILED_STATE
        ,COALESCE(SUM(CASE WHEN EVENT_TYPE = 'REQUEST' AND ADD_JOURNEY = 'LINK' THEN 1 END),0) AS LINK_PENDING_STATE
        ,COALESCE(SUM(CASE WHEN EVENT_TYPE = 'DELETE' AND ADD_JOURNEY = 'LINK' THEN 1 END),0) AS LINK_REMOVED_STATE
FROM to_from_dates u
LEFT JOIN dim_date d
    ON d.DATE >= u.FROM_DATE
    AND d.DATE < COALESCE(u.TO_DATE, '9999-12-31')
GROUP BY
    d.DATE
    ,u.BRAND
    ,u.LOYALTY_PLAN_NAME
    ,u.LOYALTY_PLAN_COMPANY
HAVING DATE IS NOT NULL
)    

,count_up_abs AS (
  SELECT
    d.DATE
    ,u.BRAND
    ,u.LOYALTY_PLAN_NAME
    ,u.LOYALTY_PLAN_COMPANY
        ,COALESCE(SUM(CASE WHEN EVENT_TYPE = 'REQUEST' AND ADD_JOURNEY = 'JOIN' THEN 1 END),0) AS JOIN_REQUEST_PENDING
        ,COALESCE(SUM(CASE WHEN EVENT_TYPE = 'FAILED' AND ADD_JOURNEY = 'JOIN' THEN 1 END),0) AS JOIN_FAILED
        ,COALESCE(SUM(CASE WHEN EVENT_TYPE = 'SUCCESS' AND ADD_JOURNEY = 'JOIN' THEN 1 END),0) AS JOIN_SUCCESSFUL
        ,COALESCE(SUM(CASE WHEN EVENT_TYPE = 'DELETE' AND ADD_JOURNEY = 'JOIN' THEN 1 END),0) AS JOIN_DELETE
  
        ,COALESCE(SUM(CASE WHEN EVENT_TYPE = 'REQUEST' AND ADD_JOURNEY = 'LINK' THEN 1 END),0) AS LINK_REQUEST_PENDING
        ,COALESCE(SUM(CASE WHEN EVENT_TYPE = 'FAILED' AND ADD_JOURNEY = 'LINK' THEN 1 END),0) AS LINK_FAILED
        ,COALESCE(SUM(CASE WHEN EVENT_TYPE = 'SUCCESS' AND ADD_JOURNEY = 'LINK' THEN 1 END),0) AS LINK_SUCCESSFUL
        ,COALESCE(SUM(CASE WHEN EVENT_TYPE = 'DELETE' AND ADD_JOURNEY = 'LINK' THEN 1 END),0) AS LINK_DELETE
FROM to_from_dates u
LEFT JOIN dim_date d
    ON d.DATE = u.FROM_DATE
GROUP BY
    d.DATE
    ,u.BRAND
    ,u.LOYALTY_PLAN_NAME
    ,u.LOYALTY_PLAN_COMPANY
HAVING DATE IS NOT NULL
)    

,all_together AS (
    SELECT
        COALESCE(a.date,s.date) DATE
        ,COALESCE(a.brand,s.brand) BRAND
        ,COALESCE(a.LOYALTY_PLAN_NAME,s.LOYALTY_PLAN_NAME) LOYALTY_PLAN_NAME
        ,COALESCE(a.LOYALTY_PLAN_COMPANY,s.LOYALTY_PLAN_COMPANY) LOYALTY_PLAN_COMPANY
        ,COALESCE(s.JOIN_SUCCESS_STATE,0) AS JOIN_SUCCESS_STATE
        ,COALESCE(s.JOIN_FAILED_STATE,0) AS JOIN_FAILED_STATE
        ,COALESCE(s.JOIN_PENDING_STATE,0) AS JOIN_PENDING_STATE
        ,COALESCE(s.JOIN_REMOVED_STATE,0) AS JOIN_REMOVED_STATE
        ,COALESCE(s.LINK_SUCCESS_STATE,0) AS LINK_SUCCESS_STATE
        ,COALESCE(s.LINK_FAILED_STATE,0) AS LINK_FAILED_STATE
        ,COALESCE(s.LINK_PENDING_STATE,0) AS LINK_PENDING_STATE
        ,COALESCE(s.LINK_REMOVED_STATE,0) AS LINK_REMOVED_STATE
        ,COALESCE(a.JOIN_REQUEST_PENDING,0) AS JOIN_REQUEST_PENDING
        ,COALESCE(a.JOIN_FAILED,0) AS JOIN_FAILED
        ,COALESCE(a.JOIN_SUCCESSFUL,0) AS JOIN_SUCCESSFUL
        ,COALESCE(a.JOIN_DELETE,0) AS JOIN_DELETE
        ,COALESCE(a.LINK_REQUEST_PENDING,0) AS LINK_REQUEST_PENDING
        ,COALESCE(a.LINK_FAILED,0) AS LINK_FAILED
        ,COALESCE(a.LINK_SUCCESSFUL,0) AS LINK_SUCCESSFUL
        ,COALESCE(a.LINK_DELETE,0) AS LINK_DELETE
    FROM count_up_abs a
    FULL OUTER JOIN count_up_snap s     
        ON a.date=s.date and a.brand = s.brand and a.loyalty_plan_name = s.loyalty_plan_name
)

,add_user_metrics AS (
    SELECT
        DATE
        ,BRAND
        ,LOYALTY_PLAN_NAME
        ,LOYALTY_PLAN_COMPANY
        ,JOIN_SUCCESS_STATE
        ,JOIN_FAILED_STATE
        ,JOIN_PENDING_STATE
        ,JOIN_REMOVED_STATE
        ,LINK_SUCCESS_STATE
        ,LINK_FAILED_STATE
        ,LINK_PENDING_STATE
        ,LINK_REMOVED_STATE
        ,JOIN_REQUEST_PENDING
        ,JOIN_FAILED
        ,JOIN_SUCCESSFUL
        ,JOIN_DELETE
        ,LINK_REQUEST_PENDING
        ,LINK_FAILED
        ,LINK_SUCCESSFUL
        ,LINK_DELETE
        ,JOIN_SUCCESS_STATE+LINK_SUCCESS_STATE AS REGISTERED_USERS
        ,LINK_REMOVED_STATE+JOIN_REMOVED_STATE AS DEREGISTERED_USERS
        ,JOIN_SUCCESSFUL+LINK_SUCCESSFUL AS DAILY_REGISTRATIONS
        ,JOIN_DELETE+LINK_DELETE AS DAILY_DEREGISTRATIONS
    FROM all_together
)

select * 
from add_user_metrics
where LOYALTY_PLAN_NAME is not null --this can be removed when datafix implemented
