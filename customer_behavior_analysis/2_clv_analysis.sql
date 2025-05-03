-- Customer Lifetime Value (LTV) Analysis
-- Step 1: Calculate comprehensive customer purchase history
WITH customer_order_history AS (
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
        DATEDIFF(DAY, c.signup_date, CURRENT_DATE()) AS customer_tenure_days,
        COUNT(DISTINCT o.order_id) AS total_orders,
        SUM(o.total_amount) AS total_spent,
        MAX(o.order_date) AS last_order_date,
        MIN(o.order_date) AS first_order_date,
        AVG(o.total_amount) AS avg_order_value,
        DATEDIFF(DAY, MIN(o.order_date), MAX(o.order_date)) AS days_between_first_last_order,
        COUNT(DISTINCT o.order_id) / 
            NULLIF(DATEDIFF(MONTH, c.signup_date, CURRENT_DATE()), 0) AS monthly_purchase_rate
    FROM ecom_db.ecom_intermediate.customers_enriched c
    LEFT JOIN ecom_db.ecom_intermediate.locations l ON c.location_id = l.location_id
    LEFT JOIN ecom_db.ecom_intermediate.orders o ON c.customer_id = o.customer_id
    GROUP BY 
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
        customer_tenure_days
),
-- Step 2: Calculate intervals between purchases for repeat customers
purchase_intervals AS (
    SELECT
        o1.customer_id,
        AVG(DATEDIFF(DAY, o1.order_date, o2.order_date)) AS avg_days_between_orders
    FROM ecom_db.ecom_intermediate.orders o1
    JOIN ecom_db.ecom_intermediate.orders o2 
        ON o1.customer_id = o2.customer_id AND o1.order_date < o2.order_date
    GROUP BY 1
    HAVING COUNT(*) > 1
),
-- Step 3: Estimate churn probability based on purchase recency and cadence
churn_probability AS (
    SELECT
        coh.customer_id,
        CASE 
            WHEN coh.total_orders = 0 THEN 1.0
            WHEN DATEDIFF(DAY, coh.last_order_date, CURRENT_DATE()) > 2 * COALESCE(pi.avg_days_between_orders, 60) THEN 0.8
            WHEN DATEDIFF(DAY, coh.last_order_date, CURRENT_DATE()) > COALESCE(pi.avg_days_between_orders, 60) THEN 0.5
            ELSE 0.2
        END AS churn_probability
    FROM customer_order_history coh
    LEFT JOIN purchase_intervals pi ON coh.customer_id = pi.customer_id
)
-- Step 4: Calculate CLV projections for different time horizons
SELECT
    coh.*,
    COALESCE(pi.avg_days_between_orders, 0) AS avg_days_between_orders,
    cp.churn_probability,
    -- Historical CLV
    coh.total_spent AS historical_clv,
    -- Projected 12-month CLV
    coh.total_spent + (
        coh.avg_order_value * 
        coh.monthly_purchase_rate * 
        12 * 
        (1 - cp.churn_probability)
    ) AS projected_annual_clv,
    -- Projected 3-year CLV with retention decay
    coh.total_spent + (
        coh.avg_order_value * 
        coh.monthly_purchase_rate * 
        36 * 
        POWER((1 - cp.churn_probability), 3)
    ) AS projected_3year_clv,
    -- Customer value tier
    CASE
        WHEN coh.total_spent = 0 THEN 'No Value'
        WHEN coh.total_spent < 100 THEN 'Low Value'
        WHEN coh.total_spent < 500 THEN 'Medium Value'
        WHEN coh.total_spent < 2000 THEN 'High Value'
        ELSE 'VIP'
    END AS value_tier
FROM customer_order_history coh
LEFT JOIN purchase_intervals pi ON coh.customer_id = pi.customer_id
LEFT JOIN churn_probability cp ON coh.customer_id = cp.customer_id