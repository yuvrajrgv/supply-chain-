-- =====================================================================
-- MySQL 8.0 Market Analysis Queries
-- Supply Chain Analytics Portfolio Project
-- Table: order_lines_extended
--
-- Grain:
--   - The source table is one row per order line.
--   - Revenue and profit are line-level measures.
--   - Delivery and cancellation metrics use distinct order_id values.
--

-- =====================================================================

USE supply_chain_analytics;

-- ---------------------------------------------------------------------
-- Question 1: What is the overall commercial performance?
-- ---------------------------------------------------------------------
SELECT
    COUNT(*) AS order_lines,
    COUNT(DISTINCT order_id) AS distinct_orders,
    COUNT(DISTINCT product_card_id) AS distinct_products,
    ROUND(SUM(sales), 2) AS gross_sales,
    ROUND(SUM(order_item_discount), 2) AS total_discount,
    ROUND(SUM(order_item_total), 2) AS net_sales,
    ROUND(SUM(order_profit_per_order), 2) AS total_profit,
    ROUND(
        100.0 * SUM(order_profit_per_order)
        / NULLIF(SUM(order_item_total), 0),
        2
    ) AS profit_margin_pct,
    ROUND(
        100.0 * SUM(order_item_discount)
        / NULLIF(SUM(sales), 0),
        2
    ) AS discount_rate_pct
FROM order_lines_extended;

-- ---------------------------------------------------------------------
-- Question 2: How do sales, profit, and order volume change monthly?
-- Includes month-over-month changes for trend interpretation.
-- ---------------------------------------------------------------------
WITH monthly AS (
    SELECT
        DATE_FORMAT(order_date, '%Y-%m') AS order_month,
        SUM(order_item_total) AS net_sales,
        SUM(order_profit_per_order) AS total_profit,
        COUNT(DISTINCT order_id) AS distinct_orders
    FROM order_lines_extended
    GROUP BY DATE_FORMAT(order_date, '%Y-%m')
),
with_previous_month AS (
    SELECT
        order_month,
        net_sales,
        total_profit,
        distinct_orders,
        LAG(net_sales) OVER (ORDER BY order_month) AS previous_month_sales,
        LAG(total_profit) OVER (ORDER BY order_month) AS previous_month_profit,
        LAG(distinct_orders) OVER (ORDER BY order_month) AS previous_month_orders
    FROM monthly
)
SELECT
    order_month,
    ROUND(net_sales, 2) AS net_sales,
    ROUND(total_profit, 2) AS total_profit,
    distinct_orders,
    ROUND(
        100.0 * (net_sales - previous_month_sales)
        / NULLIF(previous_month_sales, 0),
        2
    ) AS sales_mom_change_pct,
    ROUND(
        100.0 * (total_profit - previous_month_profit)
        / NULLIF(ABS(previous_month_profit), 0),
        2
    ) AS profit_mom_change_pct,
    ROUND(
        100.0 * (distinct_orders - previous_month_orders)
        / NULLIF(previous_month_orders, 0),
        2
    ) AS orders_mom_change_pct
FROM with_previous_month
ORDER BY order_month;

-- ---------------------------------------------------------------------
-- Question 3: Which product categories generate the highest market value?
-- Includes revenue share, profit margin, and rank.
-- ---------------------------------------------------------------------
WITH category_totals AS (
    SELECT
        category_name,
        SUM(order_item_total) AS net_sales,
        SUM(order_profit_per_order) AS total_profit,
        SUM(order_item_quantity) AS units_sold,
        COUNT(DISTINCT order_id) AS distinct_orders
    FROM order_lines_extended
    GROUP BY category_name
),
category_metrics AS (
    SELECT
        category_name,
        net_sales,
        total_profit,
        units_sold,
        distinct_orders,
        SUM(net_sales) OVER () AS company_net_sales
    FROM category_totals
)
SELECT
    DENSE_RANK() OVER (ORDER BY net_sales DESC) AS sales_rank,
    category_name,
    units_sold,
    distinct_orders,
    ROUND(net_sales, 2) AS net_sales,
    ROUND(
        100.0 * net_sales / NULLIF(company_net_sales, 0),
        2
    ) AS revenue_share_pct,
    ROUND(total_profit, 2) AS total_profit,
    ROUND(
        100.0 * total_profit / NULLIF(net_sales, 0),
        2
    ) AS profit_margin_pct
FROM category_metrics
ORDER BY sales_rank, category_name;

-- ---------------------------------------------------------------------
-- Question 4: Which products are the most commercially important?
-- Returns the top 10 by net sales with units, orders, margin, and share.
-- ---------------------------------------------------------------------
WITH product_totals AS (
    SELECT
        product_card_id,
        product_name,
        category_name,
        SUM(order_item_quantity) AS units_sold,
        COUNT(DISTINCT order_id) AS distinct_orders,
        SUM(order_item_total) AS net_sales,
        SUM(order_profit_per_order) AS total_profit
    FROM order_lines_extended
    GROUP BY product_card_id, product_name, category_name
),
product_metrics AS (
    SELECT
        product_totals.*,
        SUM(net_sales) OVER () AS company_net_sales
    FROM product_totals
)
SELECT
    ROW_NUMBER() OVER (ORDER BY net_sales DESC, product_name) AS sales_rank,
    product_name,
    category_name,
    units_sold,
    distinct_orders,
    ROUND(net_sales, 2) AS net_sales,
    ROUND(
        100.0 * net_sales / NULLIF(company_net_sales, 0),
        2
    ) AS revenue_share_pct,
    ROUND(total_profit, 2) AS total_profit,
    ROUND(
        100.0 * total_profit / NULLIF(net_sales, 0),
        2
    ) AS profit_margin_pct
FROM product_metrics
ORDER BY net_sales DESC, product_name
LIMIT 10;

-- ---------------------------------------------------------------------
-- Question 5: Which regions and markets generate the strongest results?
-- Includes revenue share, profit margin, and sales rank.
-- ---------------------------------------------------------------------
WITH region_totals AS (
    SELECT
        market,
        order_region,
        SUM(order_item_total) AS net_sales,
        SUM(order_profit_per_order) AS total_profit,
        COUNT(DISTINCT order_id) AS distinct_orders,
        SUM(order_item_quantity) AS units_sold
    FROM order_lines_extended
    GROUP BY market, order_region
),
region_metrics AS (
    SELECT
        region_totals.*,
        SUM(net_sales) OVER () AS company_net_sales
    FROM region_totals
)
SELECT
    DENSE_RANK() OVER (ORDER BY net_sales DESC) AS sales_rank,
    market,
    order_region,
    units_sold,
    distinct_orders,
    ROUND(net_sales, 2) AS net_sales,
    ROUND(
        100.0 * net_sales / NULLIF(company_net_sales, 0),
        2
    ) AS revenue_share_pct,
    ROUND(total_profit, 2) AS total_profit,
    ROUND(
        100.0 * total_profit / NULLIF(net_sales, 0),
        2
    ) AS profit_margin_pct
FROM region_metrics
ORDER BY sales_rank, market, order_region;

-- ---------------------------------------------------------------------
-- Question 6: How are discount tiers related to profitability?
-- Keeps tier logic in one place and adds average order-line economics.
-- ---------------------------------------------------------------------
WITH discount_classified AS (
    SELECT
        order_item_id,
        order_item_discount_rate,
        order_item_total,
        order_profit_per_order,
        CASE
            WHEN order_item_discount_rate = 0 THEN '0% No Discount'
            WHEN order_item_discount_rate <= 0.10 THEN '1% - 10%'
            WHEN order_item_discount_rate <= 0.20 THEN '11% - 20%'
            WHEN order_item_discount_rate <= 0.25 THEN '21% - 25%'
            ELSE 'Above 25%'
        END AS discount_tier,
        CASE
            WHEN order_item_discount_rate = 0 THEN 1
            WHEN order_item_discount_rate <= 0.10 THEN 2
            WHEN order_item_discount_rate <= 0.20 THEN 3
            WHEN order_item_discount_rate <= 0.25 THEN 4
            ELSE 5
        END AS tier_sort
    FROM order_lines_extended
),
discount_totals AS (
    SELECT
        discount_tier,
        tier_sort,
        COUNT(*) AS order_lines,
        SUM(order_item_total) AS net_sales,
        SUM(order_profit_per_order) AS total_profit,
        SUM(
            CASE WHEN order_profit_per_order < 0 THEN 1 ELSE 0 END
        ) AS loss_making_lines
    FROM discount_classified
    GROUP BY discount_tier, tier_sort
)
SELECT
    discount_tier,
    order_lines,
    ROUND(net_sales, 2) AS net_sales,
    ROUND(total_profit, 2) AS total_profit,
    ROUND(total_profit / NULLIF(order_lines, 0), 2) AS avg_profit_per_line,
    ROUND(net_sales / NULLIF(order_lines, 0), 2) AS avg_sales_per_line,
    ROUND(
        100.0 * total_profit / NULLIF(net_sales, 0),
        2
    ) AS profit_margin_pct,
    loss_making_lines,
    ROUND(
        100.0 * loss_making_lines / NULLIF(order_lines, 0),
        2
    ) AS loss_making_pct
FROM discount_totals
ORDER BY tier_sort;

-- ---------------------------------------------------------------------
-- Question 7: Which shipping modes have the highest late-delivery rates?
-- One row per order prevents multi-item orders from inflating the rates.
-- ---------------------------------------------------------------------
WITH distinct_orders AS (
    SELECT DISTINCT
        order_id,
        shipping_mode,
        delivery_status,
        days_for_shipping_real,
        days_for_shipment_scheduled
    FROM order_lines_extended
),
shipping_totals AS (
    SELECT
        shipping_mode,
        COUNT(*) AS total_orders,
        SUM(
            CASE WHEN delivery_status <> 'Shipping canceled'
                 THEN 1 ELSE 0 END
        ) AS completed_orders,
        SUM(
            CASE WHEN delivery_status = 'Late delivery'
                 THEN 1 ELSE 0 END
        ) AS late_orders,
        SUM(
            CASE WHEN delivery_status = 'Shipping canceled'
                 THEN 1 ELSE 0 END
        ) AS canceled_orders,
        AVG(
            CASE WHEN delivery_status <> 'Shipping canceled'
                 THEN days_for_shipping_real END
        ) AS avg_actual_shipping_days,
        AVG(days_for_shipment_scheduled) AS avg_scheduled_shipping_days
    FROM distinct_orders
    GROUP BY shipping_mode
)
SELECT
    shipping_mode,
    total_orders,
    completed_orders,
    late_orders,
    canceled_orders,
    ROUND(
        100.0 * completed_orders / NULLIF(total_orders, 0),
        2
    ) AS completion_rate_pct,
    ROUND(
        100.0 * late_orders / NULLIF(completed_orders, 0),
        2
    ) AS late_delivery_rate_pct,
    ROUND(avg_actual_shipping_days, 2) AS avg_actual_shipping_days,
    ROUND(avg_scheduled_shipping_days, 2) AS avg_scheduled_shipping_days,
    ROUND(
        avg_actual_shipping_days - avg_scheduled_shipping_days,
        2
    ) AS avg_schedule_variance_days
FROM shipping_totals
ORDER BY late_delivery_rate_pct DESC, shipping_mode;

-- ---------------------------------------------------------------------
-- Question 8: What is the cancellation and shipping-record exception profile?
-- Summarizes status at both line and distinct-order grain.
-- ---------------------------------------------------------------------
WITH order_flags AS (
    SELECT
        order_id,
        MAX(
            CASE WHEN delivery_status = 'Shipping canceled'
                 THEN 1 ELSE 0 END
        ) AS is_canceled_order,
        MAX(
            CASE WHEN days_for_shipping_real > days_for_shipment_scheduled
                 THEN 1 ELSE 0 END
        ) AS exceeded_schedule,
        MAX(
            CASE WHEN late_delivery_risk = 1
                 THEN 1 ELSE 0 END
        ) AS late_risk_flagged,
        MAX(
            CASE WHEN days_for_shipping_real > days_for_shipment_scheduled
                      AND late_delivery_risk = 0
                 THEN 1 ELSE 0 END
        ) AS apparent_inconsistency
    FROM order_lines_extended
    GROUP BY order_id
)
SELECT
    COUNT(*) AS distinct_orders,
    SUM(is_canceled_order) AS canceled_orders,
    SUM(exceeded_schedule) AS orders_exceeding_schedule,
    SUM(late_risk_flagged) AS orders_flagged_late_risk,
    SUM(apparent_inconsistency) AS apparent_inconsistency_orders,
    ROUND(
        100.0 * SUM(is_canceled_order) / NULLIF(COUNT(*), 0),
        2
    ) AS cancellation_rate_pct,
    ROUND(
        100.0 * SUM(apparent_inconsistency)
        / NULLIF(SUM(exceeded_schedule), 0),
        2
    ) AS inconsistency_share_of_schedule_exceptions_pct,
    ROUND(
        100.0 * SUM(apparent_inconsistency)
        / NULLIF(SUM(is_canceled_order), 0),
        2
    ) AS inconsistency_share_of_canceled_orders_pct
FROM order_flags;

-- Optional detail for investigating the exception by delivery status.
SELECT
    delivery_status,
    COUNT(*) AS order_lines,
    COUNT(DISTINCT order_id) AS distinct_orders,
    SUM(
        CASE WHEN days_for_shipping_real > days_for_shipment_scheduled
             THEN 1 ELSE 0 END
    ) AS lines_exceeding_schedule,
    SUM(
        CASE WHEN late_delivery_risk = 1
             THEN 1 ELSE 0 END
    ) AS lines_flagged_late_risk,
    SUM(
        CASE WHEN days_for_shipping_real > days_for_shipment_scheduled
                  AND late_delivery_risk = 0
             THEN 1 ELSE 0 END
    ) AS apparent_inconsistency_lines
FROM order_lines_extended
GROUP BY delivery_status
ORDER BY distinct_orders DESC, delivery_status;
