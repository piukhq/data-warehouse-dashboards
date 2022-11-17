WITH mock_brands AS (
    SELECT *
    FROM {{ref('trans__mock_brands')}}
),

,dim_lc AS (
    SELECT *
    FROM {{ref('src__dim_loyalty_card')}}
)

,transactions AS (
    SELECT *
    FROM {{ref('src__fact_transaction')}}
)

,base_table AS (
    SELECT 
        t.DATE(EVENT_DATE_TIME) AS DATE
        ,t.LOYALTY_CARD_ID
        ,t.USER_ID
        ,t.LOYALTY_PLAN_NAME
        ,t.SPEND_AMOUNT
        ,lc.LOYALTY_PLAN_COMPANY
        ,B.BRAND
    FROM transactions t
    LEFT JOIN dim_lc lc ON 
        lc.LOYALTY_CARD_ID = t.LOYALTY_CARD_ID
    LEFT JOIN mock_brands b ON
        b.USER_ID = t.USER_ID
)

SELECT * 
FROM base_table 