-- Category Performance Trends
-- Step 1: Calculate sales metrics by category and month
WITH category_sales_by_period AS (
    SELECT
        c.category_id,
        c.category_name,
        DATE_TRUNC('MONTH', o.order_date) AS sales_month,
        COUNT(DISTINCT o.order_id) AS order_count,
        COUNT(DISTINCT o.customer_id) AS customer_count,
        SUM(oi.quantity) AS units_sold,
        SUM(oi.total_price) AS revenue,
        SUM(oi.quantity * p.base_price) AS gross_merchandise_value,
        SUM(oi.total_price) / SUM(oi.quantity) AS avg_selling_price,
        SUM(oi.total_price) / COUNT(DISTINCT o.order_id) AS avg_order_value,
        AVG(r.review_score) AS avg_review_score,
        COUNT(DISTINCT r.review_id) AS review_count
    FROM ecom_db.ecom_intermediate.categories_enriched c
    JOIN ecom_db.ecom_intermediate.products_enriched p ON c.category_id = p.category_id
    JOIN ecom_db.ecom_intermediate.order_items oi ON p.product_id = oi.product_id
    JOIN ecom_db.ecom_intermediate.orders o ON oi.order_id = o.order_id
    LEFT JOIN ecom_db.ecom_intermediate.reviews_enriched r ON p.product_id = r.product_id
        AND o.order_id = r.order_id
    GROUP BY 1, 2, 3
),
-- Step 2: Calculate monthly total revenue for share calculation
monthly_totals AS (
    SELECT 
        sales_month,
        SUM(revenue) AS total_revenue
    FROM category_sales_by_period
    GROUP BY 1
),
-- Step 3: Calculate growth metrics and category share
category_growth AS (
    SELECT
        cs.*,
        mt.total_revenue AS monthly_revenue,
        cs.revenue / mt.total_revenue AS category_share,
        LAG(cs.revenue) OVER (PARTITION BY cs.category_id ORDER BY cs.sales_month) AS prev_month_revenue,
        LAG(cs.units_sold) OVER (PARTITION BY cs.category_id ORDER BY cs.sales_month) AS prev_month_units
    FROM category_sales_by_period cs
    JOIN monthly_totals mt ON cs.sales_month = mt.sales_month
)
-- Final query with growth metrics and rankings
SELECT
    category_id,
    category_name,
    sales_month,
    order_count,
    customer_count,
    units_sold,
    revenue,
    gross_merchandise_value,
    avg_selling_price,
    avg_order_value,
    avg_review_score,
    review_count,
    category_share,
    
    -- MoM Growth Metrics
    (revenue - prev_month_revenue) / NULLIF(prev_month_revenue, 0) AS revenue_growth_mom,
    (units_sold - prev_month_units) / NULLIF(prev_month_units, 0) AS units_growth_mom,
    
    -- Rolling metrics
    SUM(revenue) OVER (PARTITION BY category_id ORDER BY sales_month 
                      ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS rolling_3month_revenue,
    
    -- Rank within month
    RANK() OVER (PARTITION BY sales_month ORDER BY revenue DESC) AS revenue_rank,
    RANK() OVER (PARTITION BY sales_month ORDER BY units_sold DESC) AS units_rank
FROM category_growth
ORDER BY category_name, sales_month;