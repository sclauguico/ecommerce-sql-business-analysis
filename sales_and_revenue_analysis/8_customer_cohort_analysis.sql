-- Customer Cohort Analysis
-- Step 1: Identify first purchase date for each customer
WITH first_purchases AS (
    SELECT
        c.customer_id,
        c.first_name,
        c.last_name,
        c.email,
        c.age,
        c.gender,
        c.annual_income,
        l.city,
        l.state,
        DATE_TRUNC('MONTH', MIN(o.order_date)) AS cohort_month,
        MIN(o.order_date) AS first_purchase_date
    FROM ecom_db.ecom_intermediate.customers_enriched c
    LEFT JOIN ecom_db.ecom_intermediate.locations l ON c.location_id = l.location_id
    JOIN ecom_db.ecom_intermediate.orders o ON c.customer_id = o.customer_id
    GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9
),
-- Step 2: Calculate activity by month for each customer
customer_monthly_activity AS (
    SELECT
        fp.customer_id,
        fp.cohort_month,
        DATE_TRUNC('MONTH', o.order_date) AS activity_month,
        DATEDIFF('MONTH', fp.cohort_month, DATE_TRUNC('MONTH', o.order_date)) AS cohort_month_number,
        COUNT(DISTINCT o.order_id) AS orders,
        SUM(o.total_amount) AS spend
    FROM first_purchases fp
    JOIN ecom_db.ecom_intermediate.orders o ON fp.customer_id = o.customer_id
    GROUP BY 1, 2, 3, 4
),
-- Step 3: Calculate cohort sizes
cohort_sizes AS (
    SELECT
        cohort_month,
        COUNT(DISTINCT customer_id) AS cohort_customers
    FROM first_purchases
    GROUP BY 1
),
-- Step 4: Calculate retention and revenue metrics
retention_analysis AS (
    SELECT
        a.cohort_month,
        a.cohort_month_number,
        cs.cohort_customers,
        COUNT(DISTINCT a.customer_id) AS active_customers,
        COUNT(DISTINCT a.customer_id) / cs.cohort_customers AS retention_rate,
        SUM(a.spend) AS total_revenue,
        SUM(a.spend) / COUNT(DISTINCT a.customer_id) AS revenue_per_customer,
        SUM(a.spend) / cs.cohort_customers AS revenue_per_cohort_customer
    FROM customer_monthly_activity a
    JOIN cohort_sizes cs ON a.cohort_month = cs.cohort_month
    GROUP BY 1, 2, 3
),
-- Step 5: Calculate cohort summary metrics
cohort_metrics_by_month AS (
    SELECT
        cohort_month,
        cohort_customers,
        -- Retention after N months
        MAX(CASE WHEN cohort_month_number = 1 THEN retention_rate ELSE NULL END) AS m1_retention,
        MAX(CASE WHEN cohort_month_number = 2 THEN retention_rate ELSE NULL END) AS m2_retention,
        MAX(CASE WHEN cohort_month_number = 3 THEN retention_rate ELSE NULL END) AS m3_retention,
        MAX(CASE WHEN cohort_month_number = 6 THEN retention_rate ELSE NULL END) AS m6_retention,
        MAX(CASE WHEN cohort_month_number = 12 THEN retention_rate ELSE NULL END) AS m12_retention,
        -- Cumulative revenue per customer
        SUM(CASE WHEN cohort_month_number <= 1 THEN total_revenue ELSE 0 END) / cohort_customers AS m1_cumulative_revenue,
        SUM(CASE WHEN cohort_month_number <= 3 THEN total_revenue ELSE 0 END) / cohort_customers AS m3_cumulative_revenue,
        SUM(CASE WHEN cohort_month_number <= 6 THEN total_revenue ELSE 0 END) / cohort_customers AS m6_cumulative_revenue,
        SUM(CASE WHEN cohort_month_number <= 12 THEN total_revenue ELSE 0 END) / cohort_customers AS m12_cumulative_revenue,
        -- Average revenue per active customer by period 
        AVG(CASE WHEN cohort_month_number <= 3 THEN revenue_per_customer ELSE NULL END) AS m3_avg_revenue_per_active,
        AVG(CASE WHEN cohort_month_number > 3 AND cohort_month_number <= 6 THEN revenue_per_customer ELSE NULL END) AS m4_6_avg_revenue_per_active,
        AVG(CASE WHEN cohort_month_number > 6 THEN revenue_per_customer ELSE NULL END) AS m7plus_avg_revenue_per_active
    FROM retention_analysis
    GROUP BY 1, 2
)

-- Change the value of this parameter to switch between the two analyses
-- Set to 1 for Cohort Retention Matrix, 2 for Cohort Performance Summary
SELECT * FROM (SELECT 1 AS analysis_type) t
CROSS JOIN LATERAL (
    -- Analysis Type 1: Cohort Retention Matrix
    SELECT
        cohort_month,
        cohort_month_number,
        active_customers,
        retention_rate,
        total_revenue,
        revenue_per_customer,
        revenue_per_cohort_customer,
        NULL AS cohort_classification,
        -- Indexing to first month
        retention_rate / FIRST_VALUE(retention_rate) OVER (PARTITION BY cohort_month ORDER BY cohort_month_number) AS indexed_retention,
        revenue_per_customer / FIRST_VALUE(revenue_per_customer) OVER (PARTITION BY cohort_month ORDER BY cohort_month_number) AS indexed_revenue_per_customer,
        total_revenue / FIRST_VALUE(total_revenue) OVER (PARTITION BY cohort_month ORDER BY cohort_month_number) AS indexed_total_revenue
    FROM retention_analysis
    WHERE t.analysis_type = 1
    
    UNION ALL
    
    -- Analysis Type 2: Cohort Performance Summary
    SELECT
        cohort_month,
        NULL AS cohort_month_number,
        cohort_customers AS active_customers,
        m1_retention AS retention_rate,
        m3_cumulative_revenue AS total_revenue,
        m3_avg_revenue_per_active AS revenue_per_customer,
        m3_cumulative_revenue / cohort_customers AS revenue_per_cohort_customer,
        CASE
            WHEN m3_retention > 0.3 AND m3_cumulative_revenue > 7000 THEN 'High Value Cohort'
            WHEN m3_retention > 0.3 THEN 'High Retention Cohort'
            WHEN m3_cumulative_revenue > 7000 THEN 'High Revenue Cohort'
            ELSE 'Standard Cohort'
        END AS cohort_classification,
        m2_retention AS indexed_retention,
        m3_retention AS indexed_revenue_per_customer,
        m6_retention AS indexed_total_revenue
    FROM cohort_metrics_by_month
    WHERE t.analysis_type = 2
) result
ORDER BY cohort_month, COALESCE(cohort_month_number, 0);