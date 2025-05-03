-- Recency, Frequency, Monetary (RFM) Analysis
-- Step 1: Calculate customer purchase metrics
WITH customer_purchase_metrics AS (
    SELECT
        c.customer_id,
        c.email,
        c.first_name,
        c.last_name,
        c.signup_date,
        c.age,
        c.gender,
        c.annual_income,
        l.city,
        l.state,
        et.education_type AS education,
        DATEDIFF(DAY, MAX(o.order_date), CURRENT_DATE()) AS recency_days,
        COUNT(DISTINCT o.order_id) AS frequency,
        SUM(o.total_amount) AS monetary,
        AVG(o.total_amount) AS avg_order_value
    FROM ecom_db.ecom_intermediate.customers_enriched c
    LEFT JOIN ecom_db.ecom_intermediate.orders o ON c.customer_id = o.customer_id
    LEFT JOIN ecom_db.ecom_intermediate.education_types et ON c.education_id = et.education_id
    LEFT JOIN ecom_db.ecom_intermediate.locations l ON c.location_id = l.location_id
    GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11
),
-- Step 2: Assign RFM scores (1-5 scale)
rfm_scores AS (
    SELECT
        *,
        NTILE(5) OVER (ORDER BY recency_days) AS r_score_reversed,
        NTILE(5) OVER (ORDER BY frequency) AS f_score,
        NTILE(5) OVER (ORDER BY monetary) AS m_score,
        6 - NTILE(5) OVER (ORDER BY recency_days) AS r_score
    FROM customer_purchase_metrics
),
-- Step 3: Create meaningful segments
rfm_segments AS (
    SELECT
        *,
        r_score + f_score + m_score AS rfm_total,
        CASE
            WHEN r_score >= 4 AND f_score >= 4 AND m_score >= 4 THEN 'Champions'
            WHEN r_score >= 4 AND f_score >= 3 AND m_score >= 3 THEN 'Loyal Customers'
            WHEN r_score >= 3 AND f_score >= 1 AND m_score >= 2 THEN 'Potential Loyalists'
            WHEN r_score >= 4 AND f_score <= 2 AND m_score <= 2 THEN 'New Customers'
            WHEN r_score >= 3 AND f_score <= 2 AND m_score <= 2 THEN 'Promising'
            WHEN r_score >= 2 AND f_score >= 2 AND m_score >= 2 THEN 'Customers Needing Attention'
            WHEN r_score >= 2 AND f_score >= 2 AND m_score < 2 THEN 'At Risk'
            WHEN r_score < 2 AND f_score >= 3 AND m_score >= 3 THEN 'Can''t Lose Them'
            WHEN r_score < 2 AND f_score >= 2 AND m_score >= 2 THEN 'Hibernating'
            WHEN r_score < 2 AND f_score < 2 AND m_score < 2 THEN 'Lost'
            ELSE 'Others'
        END AS customer_segment
    FROM rfm_scores
)
-- Final query to view segmented customers with percentile
SELECT 
    *,
    PERCENT_RANK() OVER (PARTITION BY customer_segment ORDER BY rfm_total) AS segment_percentile
FROM rfm_segments
ORDER BY customer_segment, rfm_total DESC