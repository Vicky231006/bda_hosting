# backend/01_data_prep.R
# High-volume data synthesis, feature engineering, and Parquet persistence
library(data.table)
library(arrow)
library(dplyr)

set.seed(42)
dir.create("backend/data", showWarnings = FALSE, recursive = TRUE)

generate_simulated_big_data <- function(n_rows = 250000) {
  message(sprintf("Generating %d simulated retail transactions...", n_rows))
  
  customer_ids <- paste0("CUST_", sample(10000:99999, n_rows, replace = TRUE))
  order_ids    <- paste0("ORD_", sample(100000:999999, n_rows, replace = TRUE))
  skus         <- paste0("SKU_", sample(100:999, n_rows, replace = TRUE))
  sizes        <- sample(c("XS", "S", "M", "L", "XL"), n_rows, replace = TRUE)
  colors       <- sample(c("Black", "White", "Navy", "Red", "Olive"), n_rows, replace = TRUE)
  categories   <- sample(c("Dresses", "Outerwear", "Footwear", "Pants", "Accessories"), n_rows, replace = TRUE)
  price        <- round(runif(n_rows, 15, 250), 2)
  discount     <- sample(c(0, 0.10, 0.20, 0.35, 0.50), n_rows, replace = TRUE, prob = c(0.5, 0.2, 0.15, 0.1, 0.05))
  distance_km  <- round(runif(n_rows, 10, 2200), 1)
  
  dt <- data.table(
    order_id = order_ids,
    customer_id = customer_ids,
    sku = skus,
    category = categories,
    size = sizes,
    color = colors,
    unit_price = price,
    discount_rate = discount,
    shipping_distance_km = distance_km
  )
  
  # Big Data feature engineering: detect size/color bracketing
  dt[, order_basket_size := .N, by = order_id]
  dt[, sku_count_in_order := .N, by = .(order_id, sku)]
  dt[, is_bracketed := fifelse(sku_count_in_order > 1, 1L, 0L)]
  
  # Customer historical behavior profiling
  cust_profiles <- dt[, .(total_orders = uniqueN(order_id)), by = customer_id]
  cust_profiles[, cust_hist_return_rate := runif(.N, 0.05, 0.45)]
  dt <- merge(dt, cust_profiles, by = "customer_id", all.x = TRUE)
  
  # Ground truth return probability calculation
  dt[, logit_p := -1.8 + 
                  1.6 * is_bracketed + 
                  2.2 * cust_hist_return_rate + 
                  0.005 * unit_price + 
                  0.0003 * shipping_distance_km + 
                  fifelse(category %in% c("Dresses", "Footwear"), 0.6, -0.2)]
  
  dt[, return_prob := 1 / (1 + exp(-logit_p))]
  dt[, is_returned := fifelse(runif(.N) < return_prob, 1L, 0L)]
  
  # Survival time (days until returned, or right-censored at 30 days)
  dt[, days_to_event := fifelse(
    is_returned == 1L,
    pmax(1L, pmin(30L, as.integer(rnorm(.N, mean = 7, sd = 4)))),
    30L
  )]
  
  dt[, c("logit_p", "return_prob") := NULL]
  return(dt)
}

dataset <- generate_simulated_big_data(n_rows = 250000)
write_parquet(dataset, "backend/data/processed_orders.parquet")
message("Successfully generated and saved Parquet file to backend/data/processed_orders.parquet")