-- Market Basket Analysis
-- Step 1: Identify products in each order
WITH order_products AS (
    SELECT 
        o.order_id,
        oi.product_id,
        p.product_name,
        c.category_name,
        sc.subcategory_name
    FROM ecom_db.ecom_intermediate.orders o
    JOIN ecom_db.ecom_intermediate.order_items oi ON o.order_id = oi.order_id
    JOIN ecom_db.ecom_intermediate.products_enriched p ON oi.product_id = p.product_id
    JOIN ecom_db.ecom_intermediate.categories_enriched c ON p.category_id = c.category_id
    JOIN ecom_db.ecom_intermediate.subcategories_enriched sc ON p.subcategory_id = sc.subcategory_id
),
-- Step 2: Create all possible product pairs within orders
product_pairs AS (
    SELECT
        a.product_id AS product_a_id,
        a.product_name AS product_a_name,
        a.category_name AS product_a_category,
        a.subcategory_name AS product_a_subcategory,
        b.product_id AS product_b_id,
        b.product_name AS product_b_name,
        b.category_name AS product_b_category,
        b.subcategory_name AS product_b_subcategory,
        COUNT(DISTINCT a.order_id) AS co_occurrence_count
    FROM order_products a
    JOIN order_products b ON a.order_id = b.order_id AND a.product_id < b.product_id
    GROUP BY 1, 2, 3, 4, 5, 6, 7, 8
),
-- Step 3: Calculate individual product frequencies
product_frequencies AS (
    SELECT
        product_id,
        product_name,
        COUNT(DISTINCT order_id) AS frequency
    FROM order_products
    GROUP BY 1, 2
),
-- Step 4: Get total order count for calculations
total_orders AS (
    SELECT COUNT(DISTINCT order_id) AS total_order_count
    FROM ecom_db.ecom_intermediate.orders
)
-- Final query with association metrics
SELECT
    pp.product_a_id,
    pp.product_a_name,
    pp.product_a_category,
    pp.product_a_subcategory,
    pp.product_b_id,
    pp.product_b_name,
    pp.product_b_category,
    pp.product_b_subcategory,
    pp.co_occurrence_count,
    pf_a.frequency AS product_a_frequency,
    pf_b.frequency AS product_b_frequency,
    t.total_order_count,
    
    -- Support (frequency of pair divided by total orders)
    pp.co_occurrence_count / t.total_order_count AS support,
    
    -- Confidence (how often B is purchased when A is purchased)
    pp.co_occurrence_count / pf_a.frequency AS confidence_a_to_b,
    pp.co_occurrence_count / pf_b.frequency AS confidence_b_to_a,
    
    -- Lift (how much more likely B is purchased when A is purchased)
    (pp.co_occurrence_count * t.total_order_count) / 
    (pf_a.frequency * pf_b.frequency) AS lift,
    
    -- Jaccard similarity (intersection over union)
    pp.co_occurrence_count / (pf_a.frequency + pf_b.frequency - pp.co_occurrence_count) AS jaccard_similarity,
    
    -- Cross category purchase flag
    CASE WHEN pp.product_a_category != pp.product_b_category THEN 1 ELSE 0 END AS cross_category_flag
FROM product_pairs pp
JOIN product_frequencies pf_a ON pp.product_a_id = pf_a.product_id
JOIN product_frequencies pf_b ON pp.product_b_id = pf_b.product_id
CROSS JOIN total_orders t
WHERE pp.co_occurrence_count >= 10  -- Filter for meaningful associations
ORDER BY lift DESC, co_occurrence_count DESC;