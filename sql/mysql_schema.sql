-- =====================================================================
-- MySQL 8.0+ Schema for Supply Chain Analytics Portfolio Project
-- =====================================================================
-- Provenance Note:
-- Tables prefixed simulated_* and columns prefixed simulation_* contain
-- synthetic scenario data generated for what-if policy analysis.
-- They are NOT observed historical records.
-- =====================================================================

CREATE DATABASE IF NOT EXISTS supply_chain_analytics
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_0900_ai_ci;

USE supply_chain_analytics;

-- Drop dependent tables first to allow clean reruns
DROP TABLE IF EXISTS `simulated_inventory_weekly_snapshots`;
DROP TABLE IF EXISTS `simulated_purchase_order_items`;
DROP TABLE IF EXISTS `simulated_purchase_orders`;
DROP TABLE IF EXISTS `simulated_product_suppliers`;
DROP TABLE IF EXISTS `order_lines_extended`;
DROP TABLE IF EXISTS `simulated_suppliers`;
DROP TABLE IF EXISTS `dim_products_extended`;

-- ---------------------------------------------------------------------
-- 1. Product Dimension (118 rows, grain: 1 row per product)
-- ---------------------------------------------------------------------
CREATE TABLE `dim_products_extended` (
    `product_card_id` BIGINT NOT NULL,
    `product_name` VARCHAR(150) NOT NULL,
    `category_name` VARCHAR(100) NOT NULL,
    `department_name` VARCHAR(100) NOT NULL,
    `source_reference_unit_price` DOUBLE NOT NULL,
    `simulation_primary_supplier_id` VARCHAR(32) NOT NULL,
    `simulation_primary_supplier_name` VARCHAR(100) NOT NULL,
    `simulation_primary_supplier_nominal_lead_time_days` BIGINT NOT NULL,
    `simulation_reference_unit_cost` DOUBLE NOT NULL,
    `simulation_reference_unit_cost_factor` DOUBLE NOT NULL,
    `simulation_provenance` VARCHAR(50) NOT NULL,
    PRIMARY KEY (`product_card_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- ---------------------------------------------------------------------
-- 2. Simulated Supplier Dimension (12 rows, grain: 1 row per vendor)
-- ---------------------------------------------------------------------
CREATE TABLE `simulated_suppliers` (
    `supplier_id` VARCHAR(32) NOT NULL,
    `supplier_name` VARCHAR(100) NOT NULL,
    `simulated_nominal_lead_time_days` BIGINT NOT NULL,
    `simulated_on_time_probability` DOUBLE NOT NULL,
    `simulated_base_unit_cost_factor` DOUBLE NOT NULL,
    `simulated_supplier_profile_tier` VARCHAR(10) NOT NULL,
    `record_provenance` VARCHAR(50) NOT NULL,
    `supplier_notes` VARCHAR(255) NULL,
    PRIMARY KEY (`supplier_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- ---------------------------------------------------------------------
-- 3. Simulated Product-Supplier Bridge (236 rows, grain: product-supplier)
-- ---------------------------------------------------------------------
CREATE TABLE `simulated_product_suppliers` (
    `product_card_id` BIGINT NOT NULL,
    `product_name` VARCHAR(150) NOT NULL,
    `category_name` VARCHAR(100) NOT NULL,
    `supplier_id` VARCHAR(32) NOT NULL,
    `supplier_name` VARCHAR(100) NOT NULL,
    `supplier_role` VARCHAR(20) NOT NULL,
    `is_primary_supplier` TINYINT(1) NOT NULL,
    `source_reference_unit_price` DOUBLE NOT NULL,
    `simulated_unit_purchase_cost` DOUBLE NOT NULL,
    `simulated_unit_cost_factor` DOUBLE NOT NULL,
    `minimum_order_quantity` BIGINT NOT NULL,
    `order_multiple` BIGINT NOT NULL,
    `simulated_nominal_lead_time_days` BIGINT NOT NULL,
    `simulated_on_time_probability` DOUBLE NOT NULL,
    `record_provenance` VARCHAR(50) NOT NULL,
    PRIMARY KEY (`product_card_id`, `supplier_id`),
    CONSTRAINT `fk_prod_supp_product` FOREIGN KEY (`product_card_id`) REFERENCES `dim_products_extended` (`product_card_id`),
    CONSTRAINT `fk_prod_supp_supplier` FOREIGN KEY (`supplier_id`) REFERENCES `simulated_suppliers` (`supplier_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- ---------------------------------------------------------------------
-- 4. Simulated Purchase Order Headers (1,316 rows, grain: 1 row per PO)
-- ---------------------------------------------------------------------
CREATE TABLE `simulated_purchase_orders` (
    `supplier_id` VARCHAR(32) NOT NULL,
    `po_date` DATE NOT NULL,
    `expected_delivery_date` DATE NOT NULL,
    `actual_delivery_date` DATE NOT NULL,
    `actual_lead_time_days` BIGINT NOT NULL,
    `supplier_on_time_flag` TINYINT(1) NOT NULL,
    `po_id` VARCHAR(32) NOT NULL,
    `line_count` BIGINT NOT NULL,
    `simulated_total_order_value` DOUBLE NOT NULL,
    `total_quantity_ordered` BIGINT NOT NULL,
    `supplier_name` VARCHAR(100) NOT NULL,
    `simulated_nominal_lead_time_days` BIGINT NOT NULL,
    `purchase_order_status` VARCHAR(50) NOT NULL,
    `record_provenance` VARCHAR(50) NOT NULL,
    `simulation_seed` BIGINT NOT NULL,
    PRIMARY KEY (`po_id`),
    CONSTRAINT `fk_po_supplier` FOREIGN KEY (`supplier_id`) REFERENCES `simulated_suppliers` (`supplier_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- ---------------------------------------------------------------------
-- 5. Simulated Purchase Order Line Items (1,402 rows, grain: 1 row per PO item)
-- ---------------------------------------------------------------------
CREATE TABLE `simulated_purchase_order_items` (
    `po_line_id` VARCHAR(32) NOT NULL,
    `po_id` VARCHAR(32) NOT NULL,
    `supplier_id` VARCHAR(32) NOT NULL,
    `product_card_id` BIGINT NOT NULL,
    `quantity_ordered` BIGINT NOT NULL,
    `simulated_unit_purchase_cost` DOUBLE NOT NULL,
    `simulated_line_cost` DOUBLE NOT NULL,
    `on_hand_at_reorder` BIGINT NOT NULL,
    `inventory_position_at_reorder` BIGINT NOT NULL,
    `trailing_avg_daily_demand_proxy` DOUBLE NOT NULL,
    `reorder_point_at_order` BIGINT NOT NULL,
    `record_provenance` VARCHAR(50) NOT NULL,
    `simulation_seed` BIGINT NOT NULL,
    PRIMARY KEY (`po_line_id`),
    CONSTRAINT `fk_poi_po` FOREIGN KEY (`po_id`) REFERENCES `simulated_purchase_orders` (`po_id`),
    CONSTRAINT `fk_poi_product` FOREIGN KEY (`product_card_id`) REFERENCES `dim_products_extended` (`product_card_id`),
    CONSTRAINT `fk_poi_supplier` FOREIGN KEY (`supplier_id`) REFERENCES `simulated_suppliers` (`supplier_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- ---------------------------------------------------------------------
-- 6. Main Order Line Table (180,519 rows, grain: 1 row per order item)
-- ---------------------------------------------------------------------
CREATE TABLE `order_lines_extended` (
    `transaction_type` VARCHAR(20) NOT NULL,
    `days_for_shipping_real` BIGINT NOT NULL,
    `days_for_shipment_scheduled` BIGINT NOT NULL,
    `sales_per_customer` DOUBLE NOT NULL,
    `delivery_status` VARCHAR(50) NOT NULL,
    `late_delivery_risk` BIGINT NOT NULL,
    `category_name` VARCHAR(100) NOT NULL,
    `customer_segment` VARCHAR(50) NOT NULL,
    `department_id` BIGINT NOT NULL,
    `department_name` VARCHAR(100) NOT NULL,
    `market` VARCHAR(50) NOT NULL,
    `order_city` VARCHAR(100) NOT NULL,
    `order_country` VARCHAR(100) NOT NULL,
    `order_date` DATETIME NOT NULL,
    `order_id` BIGINT NOT NULL,
    `order_item_discount` DOUBLE NOT NULL,
    `order_item_discount_rate` DOUBLE NOT NULL,
    `order_item_id` BIGINT NOT NULL,
    `order_item_product_price` DOUBLE NOT NULL,
    `order_item_profit_ratio` DOUBLE NOT NULL,
    `order_item_quantity` BIGINT NOT NULL,
    `sales` DOUBLE NOT NULL,
    `order_item_total` DOUBLE NOT NULL,
    `order_profit_per_order` DOUBLE NOT NULL,
    `order_region` VARCHAR(100) NOT NULL,
    `order_state` VARCHAR(100) NOT NULL,
    `order_status` VARCHAR(50) NOT NULL,
    `product_card_id` BIGINT NOT NULL,
    `product_category_id` BIGINT NOT NULL,
    `product_name` VARCHAR(150) NOT NULL,
    `product_price` DOUBLE NOT NULL,
    `product_status` BIGINT NOT NULL,
    `shipping_date` DATETIME NOT NULL,
    `shipping_mode` VARCHAR(50) NOT NULL,
    `order_week_start` DATE NOT NULL,
    `simulation_primary_supplier_id` VARCHAR(32) NOT NULL,
    `simulation_primary_supplier_name` VARCHAR(100) NOT NULL,
    `simulation_primary_supplier_nominal_lead_time_days` BIGINT NOT NULL,
    `simulation_reference_unit_cost` DOUBLE NOT NULL,
    `simulation_estimated_procurement_cost` DOUBLE NOT NULL,
    `simulation_estimated_merchandise_profit_pre_logistics` DOUBLE NOT NULL,
    `simulation_estimated_merchandise_margin_pct_pre_logistics` DOUBLE NOT NULL,
    `source_provenance` VARCHAR(50) NOT NULL,
    `simulation_provenance` VARCHAR(50) NOT NULL,
    PRIMARY KEY (`order_item_id`),
    CONSTRAINT `fk_order_product` FOREIGN KEY (`product_card_id`) REFERENCES `dim_products_extended` (`product_card_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- ---------------------------------------------------------------------
-- 7. Simulated Inventory Weekly Snapshots (8,552 rows, grain: product-week)
-- ---------------------------------------------------------------------
CREATE TABLE `simulated_inventory_weekly_snapshots` (
    `product_card_id` BIGINT NOT NULL,
    `week_start` DATE NOT NULL,
    `simulation_start_date` DATE NOT NULL,
    `simulation_end_date` DATE NOT NULL,
    `opening_on_hand_units` BIGINT NOT NULL,
    `opening_on_order_units` BIGINT NOT NULL,
    `weekly_receipts_units` BIGINT NOT NULL,
    `observed_completed_order_demand_proxy_units` BIGINT NOT NULL,
    `simulated_fulfilled_units` BIGINT NOT NULL,
    `simulated_unfulfilled_units` BIGINT NOT NULL,
    `closing_on_hand_units` BIGINT NOT NULL,
    `closing_on_order_units` BIGINT NOT NULL,
    `closing_inventory_position_units` BIGINT NOT NULL,
    `reorder_point_units_at_week_end` BIGINT NOT NULL,
    `safety_stock_units_at_week_end` BIGINT NOT NULL,
    `simulated_stockout_flag` TINYINT(1) NOT NULL,
    `initial_stock_units` BIGINT NOT NULL,
    `record_provenance` VARCHAR(50) NOT NULL,
    `simulation_seed` BIGINT NOT NULL,
    PRIMARY KEY (`product_card_id`, `week_start`),
    CONSTRAINT `fk_inv_product` FOREIGN KEY (`product_card_id`) REFERENCES `dim_products_extended` (`product_card_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- ---------------------------------------------------------------------
-- Performance Indexes
-- ---------------------------------------------------------------------
CREATE INDEX `idx_order_lines_order_date` ON `order_lines_extended` (`order_date`);
CREATE INDEX `idx_order_lines_order_id` ON `order_lines_extended` (`order_id`);
CREATE INDEX `idx_order_lines_product_id` ON `order_lines_extended` (`product_card_id`);
CREATE INDEX `idx_order_lines_shipping_mode` ON `order_lines_extended` (`shipping_mode`);
CREATE INDEX `idx_order_lines_status` ON `order_lines_extended` (`order_status`);
CREATE INDEX `idx_order_lines_week_start` ON `order_lines_extended` (`order_week_start`);
CREATE INDEX `idx_sim_po_supplier_date` ON `simulated_purchase_orders` (`supplier_id`, `po_date`);
CREATE INDEX `idx_sim_po_items_product` ON `simulated_purchase_order_items` (`product_card_id`);
CREATE INDEX `idx_sim_inventory_week` ON `simulated_inventory_weekly_snapshots` (`week_start`);

-- Recommended Ingestion Order:
-- 1. dim_products_extended
-- 2. simulated_suppliers
-- 3. simulated_product_suppliers
-- 4. simulated_purchase_orders
-- 5. simulated_purchase_order_items
-- 6. order_lines_extended
-- 7. simulated_inventory_weekly_snapshots
