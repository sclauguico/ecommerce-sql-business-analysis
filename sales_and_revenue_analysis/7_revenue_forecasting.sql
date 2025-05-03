-- Revenue Forecasting with Window Functions
-- Step 1: Aggregate daily sales to monthly level
WITH daily_revenue AS (
    SELECT
        DATE_TRUNC('DAY', order_date) AS sale_date,
        SUM(total_amount) AS daily_revenue
    FROM ecom_db.ecom_intermediate.orders
    GROUP BY 1
),
monthly_revenue AS (
    SELECT
        DATE_TRUNC('MONTH', sale_date) AS month,
        SUM(daily_revenue) AS monthly_revenue
    FROM daily_revenue
    GROUP BY 1
),
-- Step 2: Calculate growth rates and moving averages
revenue_with_growth AS (
    SELECT
        month,
        monthly_revenue,
        LAG(monthly_revenue) OVER (ORDER BY month) AS prev_month_revenue,
        monthly_revenue / NULLIF(LAG(monthly_revenue) OVER (ORDER BY month), 0) - 1 AS mom_growth_rate,
        monthly_revenue / NULLIF(LAG(monthly_revenue, 12) OVER (ORDER BY month), 0) - 1 AS yoy_growth_rate,
        AVG(monthly_revenue) OVER (ORDER BY month ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS ma3,
        AVG(monthly_revenue) OVER (ORDER BY month ROWS BETWEEN 11 PRECEDING AND CURRENT ROW) AS ma12,
        ROW_NUMBER() OVER (ORDER BY month) AS month_index
    FROM monthly_revenue
),
-- Step 3: Calculate trend-based forecasts
simple_growth_trends AS (
    SELECT
        month,
        monthly_revenue,
        mom_growth_rate,
        yoy_growth_rate,
        -- Average growth rate over last 6 months
        AVG(mom_growth_rate) OVER (ORDER BY month ROWS BETWEEN 5 PRECEDING AND CURRENT ROW) AS avg_growth_6m,
        -- Average YoY growth rate
        AVG(yoy_growth_rate) OVER (ORDER BY month ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS avg_yoy_growth_3m,
        ma3,
        ma12,
        month_index
    FROM revenue_with_growth
    WHERE mom_growth_rate IS NOT NULL
),
-- Step 4: Generate forecasts using different methods
forecast_data AS (
    SELECT
        month,
        monthly_revenue AS actual_revenue,
        LEAD(monthly_revenue, 1) OVER (ORDER BY month) AS next_month_actual,
        LEAD(monthly_revenue, 3) OVER (ORDER BY month) AS three_month_actual,
        -- Simple trend-based forecasts
        monthly_revenue * (1 + mom_growth_rate) AS trend_forecast_1m,
        monthly_revenue * POWER(1 + mom_growth_rate, 3) AS trend_forecast_3m,
        -- Moving average forecast
        ma3 AS ma3_forecast,
        -- Growth-based forecast
        monthly_revenue * (1 + avg_growth_6m) AS growth_forecast_1m,
        monthly_revenue * POWER(1 + avg_growth_6m, 3) AS growth_forecast_3m,
        -- Seasonal forecast (combining YoY with recent trend)
        monthly_revenue * (1 + (avg_yoy_growth_3m + avg_growth_6m) / 2) AS seasonal_forecast_1m,
        -- Hybrid forecast (average of methods)
        (monthly_revenue * (1 + mom_growth_rate) + 
         ma3 + 
         monthly_revenue * (1 + avg_growth_6m)) / 3 AS hybrid_forecast_1m
    FROM simple_growth_trends
)
-- Final query with forecast accuracy
SELECT
    month,
    actual_revenue,
    next_month_actual,
    three_month_actual,
    trend_forecast_1m,
    growth_forecast_1m,
    seasonal_forecast_1m,
    hybrid_forecast_1m,
    trend_forecast_3m,
    growth_forecast_3m,
    
    -- Forecast accuracy (comparing to actual)
    ABS(trend_forecast_1m - next_month_actual) / NULLIF(next_month_actual, 0) AS trend_1m_error,
    ABS(growth_forecast_1m - next_month_actual) / NULLIF(next_month_actual, 0) AS growth_1m_error,
    ABS(seasonal_forecast_1m - next_month_actual) / NULLIF(next_month_actual, 0) AS seasonal_1m_error,
    ABS(hybrid_forecast_1m - next_month_actual) / NULLIF(next_month_actual, 0) AS hybrid_1m_error,
    
    -- 3-month forecast accuracy
    ABS(trend_forecast_3m - three_month_actual) / NULLIF(three_month_actual, 0) AS trend_3m_error,
    ABS(growth_forecast_3m - three_month_actual) / NULLIF(three_month_actual, 0) AS growth_3m_error
FROM forecast_data
WHERE next_month_actual IS NOT NULL
ORDER BY month;