-- Seasonal Analysis
-- Step 1: Aggregate sales metrics by day with time period classifications
WITH daily_sales AS (
    SELECT
        DATE_TRUNC('DAY', o.order_date) AS sale_date,
        EXTRACT(YEAR FROM o.order_date) AS year,
        EXTRACT(MONTH FROM o.order_date) AS month,
        EXTRACT(DAY FROM o.order_date) AS day,
        EXTRACT(DAYOFWEEK FROM o.order_date) AS day_of_week,
        EXTRACT(QUARTER FROM o.order_date) AS quarter,
        CASE 
            WHEN EXTRACT(MONTH FROM o.order_date) IN (12, 1, 2) THEN 'Winter'
            WHEN EXTRACT(MONTH FROM o.order_date) IN (3, 4, 5) THEN 'Spring'
            WHEN EXTRACT(MONTH FROM o.order_date) IN (6, 7, 8) THEN 'Summer'
            ELSE 'Fall'
        END AS season,
        CASE
            WHEN EXTRACT(MONTH FROM o.order_date) = 11 AND EXTRACT(DAY FROM o.order_date) >= 26 THEN 'Black Friday/Cyber Monday'
            WHEN EXTRACT(MONTH FROM o.order_date) = 12 AND EXTRACT(DAY FROM o.order_date) >= 10 AND EXTRACT(DAY FROM o.order_date) <= 24 THEN 'Holiday Shopping'
            WHEN EXTRACT(MONTH FROM o.order_date) = 2 AND EXTRACT(DAY FROM o.order_date) >= 1 AND EXTRACT(DAY FROM o.order_date) <= 14 THEN 'Valentine''s Day'
            WHEN EXTRACT(MONTH FROM o.order_date) = 7 AND EXTRACT(DAY FROM o.order_date) >= 1 AND EXTRACT(DAY FROM o.order_date) <= 31 THEN 'Summer Sale'
            WHEN EXTRACT(MONTH FROM o.order_date) = 8 AND EXTRACT(DAY FROM o.order_date) >= 15 AND EXTRACT(DAY FROM o.order_date) <= 31 THEN 'Back to School'
            WHEN EXTRACT(MONTH FROM o.order_date) = 5 AND EXTRACT(DAY FROM o.order_date) >= 1 AND EXTRACT(DAY FROM o.order_date) <= 10 THEN 'Mother''s Day'
            WHEN EXTRACT(MONTH FROM o.order_date) = 6 AND EXTRACT(DAY FROM o.order_date) >= 10 AND EXTRACT(DAY FROM o.order_date) <= 20 THEN 'Father''s Day'
            WHEN EXTRACT(MONTH FROM o.order_date) = 4 AND EXTRACT(DAY FROM o.order_date) >= 10 AND EXTRACT(DAY FROM o.order_date) <= 25 THEN 'Spring Sale'
            ELSE 'Regular Period'
        END AS shopping_period,
        -- Sales metrics
        COUNT(DISTINCT o.order_id) AS order_count,
        SUM(o.total_amount) AS daily_revenue,
        COUNT(DISTINCT o.customer_id) AS customer_count
    FROM ecom_db.ecom_intermediate.orders o
    GROUP BY 1, 2, 3, 4, 5, 6, 7, 8
),
-- Step 2: Calculate moving averages and period benchmarks
rolling_aggregates AS (
    SELECT
        sale_date,
        year,
        month,
        day,
        day_of_week,
        quarter,
        season,
        shopping_period,
        order_count,
        daily_revenue,
        customer_count,
        -- 7-day moving average
        AVG(daily_revenue) OVER (ORDER BY sale_date ROWS BETWEEN 6 PRECEDING AND CURRENT ROW) AS ma7_revenue,
        -- 28-day moving average (approximating monthly)
        AVG(daily_revenue) OVER (ORDER BY sale_date ROWS BETWEEN 27 PRECEDING AND CURRENT ROW) AS ma28_revenue,
        -- Day of week average
        AVG(daily_revenue) OVER (PARTITION BY day_of_week) AS avg_day_of_week_revenue,
        -- Month average
        AVG(daily_revenue) OVER (PARTITION BY month) AS avg_month_revenue
    FROM daily_sales
)

SELECT 
    month,
    season,
    AVG(daily_revenue) AS avg_daily_revenue,
    SUM(daily_revenue) AS total_revenue,
    SUM(order_count) AS total_orders,
    SUM(customer_count) AS total_customers,
    AVG(daily_revenue) / AVG(avg_month_revenue) AS seasonal_index
FROM rolling_aggregates
GROUP BY month, season
ORDER BY month, season;

-- Category Seasonal Patterns
WITH category_daily_sales AS (
    SELECT
        DATE_TRUNC('DAY', o.order_date) AS sale_date,
        c.category_name,
        sc.subcategory_name,
        COUNT(DISTINCT o.order_id) AS order_count,
        SUM(oi.total_price) AS category_revenue,
        SUM(oi.quantity) AS units_sold
    FROM ecom_db.ecom_intermediate.orders o
    JOIN ecom_db.ecom_intermediate.order_items oi ON o.order_id = oi.order_id
    JOIN ecom_db.ecom_intermediate.products_enriched p ON oi.product_id = p.product_id
    JOIN ecom_db.ecom_intermediate.categories_enriched c ON p.category_id = c.category_id
    JOIN ecom_db.ecom_intermediate.subcategories_enriched sc ON p.subcategory_id = sc.subcategory_id
    GROUP BY sale_date, c.category_name, sc.subcategory_name
)

SELECT
    month_number,
    season_name,
    category_name,
    SUM(category_revenue) AS total_revenue,
    SUM(units_sold) AS total_units,
    AVG(category_revenue) AS avg_daily_revenue,
    -- Category seasonal index
    SUM(category_revenue) / 
      (SELECT AVG(cat_revenue) 
       FROM (SELECT DATE_TRUNC('MONTH', sale_date) AS month, 
                    category_name, 
                    SUM(category_revenue) AS cat_revenue 
             FROM category_daily_sales 
             GROUP BY month, category_name) x 
       WHERE x.category_name = category_daily_sales.category_name) AS category_seasonal_index
FROM 
    (SELECT
        EXTRACT(MONTH FROM sale_date) AS month_number,
        CASE 
            WHEN EXTRACT(MONTH FROM sale_date) IN (12, 1, 2) THEN 'Winter'
            WHEN EXTRACT(MONTH FROM sale_date) IN (3, 4, 5) THEN 'Spring'
            WHEN EXTRACT(MONTH FROM sale_date) IN (6, 7, 8) THEN 'Summer'
            ELSE 'Fall'
        END AS season_name,
        category_name,
        category_revenue,
        units_sold
    FROM category_daily_sales) category_daily_sales
GROUP BY month_number, season_name, category_name
ORDER BY category_name, month_number;