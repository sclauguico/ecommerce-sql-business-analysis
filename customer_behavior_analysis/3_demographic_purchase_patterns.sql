-- Purchase Patterns by Demographics
-- Step 1: Create demographic segments
WITH demographic_segments AS (
    SELECT
        customer_id,
        -- Age segments
        CASE
            WHEN age < 30 THEN 'Gen Z (18-29)'
            WHEN age BETWEEN 30 AND 39 THEN 'Millennials (30-39)'
            WHEN age BETWEEN 40 AND 49 THEN 'Xennials (40-49)'
            WHEN age BETWEEN 50 AND 59 THEN 'Gen X (50-59)'
            WHEN age BETWEEN 60 AND 69 THEN 'Younger Boomers (60-69)'
            WHEN age >= 70 THEN 'Older Boomers (70+)'
            ELSE 'Unknown Age'
        END AS age_segment,
        -- Income segments
        CASE
            WHEN annual_income < 30000 THEN 'Low Income (<$30K)'
            WHEN annual_income BETWEEN 30000 AND 59999 THEN 'Lower-Middle ($30K-$60K)'
            WHEN annual_income BETWEEN 60000 AND 99999 THEN 'Upper-Middle ($60K-$100K)'
            WHEN annual_income >= 100000 THEN 'High Income ($100K+)'
            ELSE 'Unknown Income'
        END AS income_segment,
        gender,
        et.education_type AS education,
        l.city,
        l.state,
        ms.status_type AS marital_status
    FROM ecom_db.ecom_intermediate.customers_enriched c
    LEFT JOIN ecom_db.ecom_intermediate.education_types et ON c.education_id = et.education_id
    LEFT JOIN ecom_db.ecom_intermediate.locations l ON c.location_id = l.location_id
    LEFT JOIN ecom_db.ecom_intermediate.marital_statuses ms ON c.marital_status_id = ms.marital_status_id
),
-- Step 2: Calculate purchase metrics for each customer
purchase_metrics AS (
    SELECT
        ds.*,
        COUNT(DISTINCT o.order_id) AS total_orders,
        SUM(o.total_amount) AS total_spent,
        AVG(o.total_amount) AS avg_order_value,
        MAX(o.order_date) AS last_order_date,
        COUNT(DISTINCT o.order_id) / NULLIF(COUNT(DISTINCT EXTRACT(MONTH FROM o.order_date)), 0) AS monthly_purchase_frequency
    FROM demographic_segments ds
    LEFT JOIN ecom_db.ecom_intermediate.orders o ON ds.customer_id = o.customer_id
    GROUP BY ds.customer_id, ds.age_segment, ds.income_segment, ds.gender, 
             ds.education, ds.city, ds.state, ds.marital_status
),
-- Step 3: Create category preferences by demographic segment
category_preferences AS (
    SELECT
        pm.customer_id,
        pm.age_segment,
        pm.income_segment,
        pm.gender,
        c.category_name,
        COUNT(DISTINCT oi.order_id) AS category_orders,
        SUM(oi.total_price) AS category_spent
    FROM purchase_metrics pm
    JOIN ecom_db.ecom_intermediate.order_items oi ON pm.customer_id = oi.customer_id
    JOIN ecom_db.ecom_intermediate.products_enriched p ON oi.product_id = p.product_id
    JOIN ecom_db.ecom_intermediate.categories_enriched c ON p.category_id = c.category_id
    GROUP BY 1, 2, 3, 4, 5
),
-- Combined demographic aggregations
-- Step 4: Aggregate metrics by demographic segments
demographic_aggregations AS (
    -- Aggregate by Age Segment
    SELECT
        'Age: ' || age_segment AS segment_name,
        COUNT(DISTINCT customer_id) AS customer_count,
        SUM(total_orders) AS total_orders,
        SUM(total_spent) AS total_revenue,
        AVG(avg_order_value) AS avg_order_value,
        AVG(monthly_purchase_frequency) AS avg_monthly_frequency,
        AVG(total_spent) / COUNT(DISTINCT customer_id) AS revenue_per_customer
    FROM purchase_metrics
    GROUP BY age_segment
    
    UNION ALL
    
    -- Aggregate by Income Segment
    SELECT
        'Income: ' || income_segment AS segment_name,
        COUNT(DISTINCT customer_id) AS customer_count,
        SUM(total_orders) AS total_orders,
        SUM(total_spent) AS total_revenue,
        AVG(avg_order_value) AS avg_order_value,
        AVG(monthly_purchase_frequency) AS avg_monthly_frequency,
        AVG(total_spent) / COUNT(DISTINCT customer_id) AS revenue_per_customer
    FROM purchase_metrics
    GROUP BY income_segment
    
    UNION ALL
    
    -- Aggregate by State
    SELECT
        'State: ' || state AS segment_name,
        COUNT(DISTINCT customer_id) AS customer_count,
        SUM(total_orders) AS total_orders,
        SUM(total_spent) AS total_revenue,
        AVG(avg_order_value) AS avg_order_value,
        AVG(monthly_purchase_frequency) AS avg_monthly_frequency,
        AVG(total_spent) / COUNT(DISTINCT customer_id) AS revenue_per_customer
    FROM purchase_metrics
    GROUP BY state
),
-- Category preferences by age segment, income segment, and gender
category_aggregations AS (
    -- Category preferences by age segment
    SELECT 
        'Age: ' || age_segment AS segment_name,
        category_name,
        COUNT(DISTINCT customer_id) AS customer_count,
        SUM(category_orders) AS total_orders,
        SUM(category_spent) AS total_spent,
        RATIO_TO_REPORT(SUM(category_spent)) OVER (PARTITION BY age_segment) AS category_share_of_wallet
    FROM category_preferences
    GROUP BY age_segment, category_name
    
    UNION ALL
    
    -- Category preferences by income segment
    SELECT 
        'Income: ' || income_segment AS segment_name,
        category_name,
        COUNT(DISTINCT customer_id) AS customer_count,
        SUM(category_orders) AS total_orders,
        SUM(category_spent) AS total_spent,
        RATIO_TO_REPORT(SUM(category_spent)) OVER (PARTITION BY income_segment) AS category_share_of_wallet
    FROM category_preferences
    GROUP BY income_segment, category_name
    
    UNION ALL
    
    -- Category preferences by gender
    SELECT 
        'Gender: ' || gender AS segment_name,
        category_name,
        COUNT(DISTINCT customer_id) AS customer_count,
        SUM(category_orders) AS total_orders,
        SUM(category_spent) AS total_spent,
        RATIO_TO_REPORT(SUM(category_spent)) OVER (PARTITION BY gender) AS category_share_of_wallet
    FROM category_preferences
    GROUP BY gender, category_name
)

-- Select from the first query. Comment out for the second query
SELECT * FROM demographic_aggregations
ORDER BY segment_name, total_revenue DESC

-- -- Run this separately (by uncommenting) for the the category preferences 
-- SELECT * FROM category_aggregations
-- ORDER BY segment_name, category_share_of_wallet DESC