-- Sales Funnel Conversion Analysis
-- Step 1: Identify customer interactions and purchase events
WITH customer_journey_stages AS (
    SELECT
        ci.customer_id,
        ci.product_id,
        ci.event_type,
        ci.event_date,
        ci.device_type,
        ci.session_id,
        p.product_name,
        p.category_id,
        c.category_name,
        -- Flag product purchases from order data
        CASE WHEN o.order_id IS NOT NULL THEN 1 ELSE 0 END AS purchased_flag
    FROM ecom_db.ecom_intermediate.customer_interactions ci
    JOIN ecom_db.ecom_intermediate.products_enriched p ON ci.product_id = p.product_id
    JOIN ecom_db.ecom_intermediate.categories_enriched c ON p.category_id = c.category_id
    LEFT JOIN ecom_db.ecom_intermediate.order_items oi ON ci.product_id = oi.product_id 
        AND ci.customer_id = oi.customer_id
    LEFT JOIN ecom_db.ecom_intermediate.orders o ON oi.order_id = o.order_id 
        AND ci.customer_id = o.customer_id
        AND o.order_date >= ci.event_date
),
-- Step 2: Aggregate events by funnel stage
funnel_events AS (
    SELECT
        customer_id,
        DATE_TRUNC('DAY', event_date) AS event_day,
        session_id,
        product_id,
        category_id,
        category_name,
        device_type,
        -- Identify customer stage in the funnel
        MAX(CASE WHEN event_type = 'view' THEN 1 ELSE 0 END) AS view_flag,
        MAX(CASE WHEN event_type = 'search' THEN 1 ELSE 0 END) AS search_flag,
        MAX(CASE WHEN event_type = 'cart_add' THEN 1 ELSE 0 END) AS cart_add_flag,
        MAX(CASE WHEN event_type = 'cart_remove' THEN 1 ELSE 0 END) AS cart_remove_flag,
        MAX(purchased_flag) AS purchase_flag,
        -- Calculate adjusted cart adds (cart adds minus cart removes)
        MAX(CASE WHEN event_type = 'cart_add' THEN 1 ELSE 0 END) - 
            MAX(CASE WHEN event_type = 'cart_remove' THEN 1 ELSE 0 END) AS net_cart_adds
    FROM customer_journey_stages
    GROUP BY 1, 2, 3, 4, 5, 6, 7
),
-- Step 3: Calculate daily conversion rates by funnel stage
funnel_progression AS (
    SELECT
        event_day,
        category_name,
        device_type,
        COUNT(DISTINCT CASE WHEN search_flag = 1 THEN session_id END) AS unique_searches,
        COUNT(DISTINCT CASE WHEN view_flag = 1 THEN session_id END) AS unique_views,
        COUNT(DISTINCT CASE WHEN cart_add_flag = 1 THEN session_id END) AS unique_cart_adds,
        COUNT(DISTINCT CASE WHEN net_cart_adds > 0 THEN session_id END) AS unique_net_cart_adds,
        COUNT(DISTINCT CASE WHEN purchase_flag = 1 THEN session_id END) AS unique_purchases,
        -- Conversion rates by session
        COUNT(DISTINCT CASE WHEN view_flag = 1 THEN session_id END) / 
            NULLIF(COUNT(DISTINCT CASE WHEN search_flag = 1 THEN session_id END), 0) AS search_to_view_rate,
        COUNT(DISTINCT CASE WHEN cart_add_flag = 1 THEN session_id END) / 
            NULLIF(COUNT(DISTINCT CASE WHEN view_flag = 1 THEN session_id END), 0) AS view_to_cart_rate,
        COUNT(DISTINCT CASE WHEN net_cart_adds > 0 THEN session_id END) / 
            NULLIF(COUNT(DISTINCT CASE WHEN cart_add_flag = 1 THEN session_id END), 0) AS cart_retention_rate,
        COUNT(DISTINCT CASE WHEN purchase_flag = 1 THEN session_id END) / 
            NULLIF(COUNT(DISTINCT CASE WHEN net_cart_adds > 0 THEN session_id END), 0) AS cart_to_purchase_rate,
        -- End-to-end funnel conversion
        COUNT(DISTINCT CASE WHEN purchase_flag = 1 THEN session_id END) / 
            NULLIF(COUNT(DISTINCT session_id), 0) AS session_conversion_rate
    FROM funnel_events
    GROUP BY 1, 2, 3
),
-- Step 4: Calculate customer-level funnel metrics
customer_level_funnel AS (
    SELECT
        customer_id,
        -- Calculate progress through the funnel for each customer
        MAX(search_flag) AS reached_search,
        MAX(view_flag) AS reached_view,
        MAX(cart_add_flag) AS reached_cart_add,
        MAX(CASE WHEN net_cart_adds > 0 THEN 1 ELSE 0 END) AS reached_net_cart_add,
        MAX(purchase_flag) AS reached_purchase,
        -- Count interactions
        SUM(search_flag) AS search_count,
        SUM(view_flag) AS view_count,
        SUM(cart_add_flag) AS cart_add_count,
        SUM(net_cart_adds) AS net_cart_adds_count,
        SUM(purchase_flag) AS purchase_count,
        -- Calculate drop-off stage
        CASE
            WHEN MAX(purchase_flag) = 1 THEN 'Completed Purchase'
            WHEN MAX(CASE WHEN net_cart_adds > 0 THEN 1 ELSE 0 END) = 1 THEN 'Abandoned Cart'
            WHEN MAX(cart_add_flag) = 1 THEN 'Removed from Cart'
            WHEN MAX(view_flag) = 1 THEN 'Viewed Only'
            WHEN MAX(search_flag) = 1 THEN 'Searched Only'
            ELSE 'No Engagement'
        END AS funnel_stage
    FROM funnel_events
    GROUP BY 1
)

-- To switch between analyses, uncomment the one you want to run and comment out the others

-- Analysis 1: Daily Funnel Performance
SELECT
    event_day,
    unique_searches,
    unique_views,
    unique_cart_adds,
    unique_net_cart_adds,
    unique_purchases,
    search_to_view_rate,
    view_to_cart_rate,
    cart_retention_rate,
    cart_to_purchase_rate,
    session_conversion_rate,
    -- Calculate overall funnel effectiveness
    (search_to_view_rate * view_to_cart_rate * cart_retention_rate * cart_to_purchase_rate) AS funnel_efficiency
FROM funnel_progression
WHERE unique_searches > 0
GROUP BY 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11
ORDER BY event_day;

-- Analysis 2: Category Funnel Performance
-- SELECT
--     category_name,
--     SUM(unique_searches) AS unique_searches,
--     SUM(unique_views) AS unique_views,
--     SUM(unique_cart_adds) AS unique_cart_adds,
--     SUM(unique_net_cart_adds) AS unique_net_cart_adds,
--     SUM(unique_purchases) AS unique_purchases,
--     SUM(unique_views) / NULLIF(SUM(unique_searches), 0) AS search_to_view_rate,
--     SUM(unique_cart_adds) / NULLIF(SUM(unique_views), 0) AS view_to_cart_rate,
--     SUM(unique_net_cart_adds) / NULLIF(SUM(unique_cart_adds), 0) AS cart_retention_rate,
--     SUM(unique_purchases) / NULLIF(SUM(unique_net_cart_adds), 0) AS cart_to_purchase_rate,
--     SUM(unique_purchases) / NULLIF(SUM(unique_searches), 0) AS session_conversion_rate,
--     (SUM(unique_views) / NULLIF(SUM(unique_searches), 0)) * 
--     (SUM(unique_cart_adds) / NULLIF(SUM(unique_views), 0)) * 
--     (SUM(unique_net_cart_adds) / NULLIF(SUM(unique_cart_adds), 0)) * 
--     (SUM(unique_purchases) / NULLIF(SUM(unique_net_cart_adds), 0)) AS funnel_efficiency
-- FROM funnel_progression
-- GROUP BY 1
-- ORDER BY funnel_efficiency DESC;

-- Analysis 3: Customer Funnel Distribution
-- SELECT
--     funnel_stage,
--     COUNT(DISTINCT customer_id) AS customer_count,
--     COUNT(DISTINCT customer_id) / SUM(COUNT(DISTINCT customer_id)) OVER () AS customer_percentage,
--     AVG(search_count) AS avg_searches,
--     AVG(view_count) AS avg_views,
--     AVG(cart_add_count) AS avg_cart_adds,
--     AVG(net_cart_adds_count) AS avg_net_cart_adds,
--     AVG(purchase_count) AS avg_purchases
-- FROM customer_level_funnel
-- GROUP BY 1
-- ORDER BY customer_count DESC;