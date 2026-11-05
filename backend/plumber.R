# backend/plumber.R
library(plumber)
library(xgboost)
library(survival)
library(jsonlite)

# Robust path detection for model artifacts
model_path <- if (file.exists("xgb_return_model.model")) {
  "xgb_return_model.model"
} else if (file.exists("backend/xgb_return_model.model")) {
  "backend/xgb_return_model.model"
} else {
  stop("xgb_return_model.model not found.")
}

cox_path <- if (file.exists("cox_survival_model.rds")) {
  "cox_survival_model.rds"
} else if (file.exists("backend/cox_survival_model.rds")) {
  "backend/cox_survival_model.rds"
} else {
  stop("cox_survival_model.rds not found.")
}

xgb_model <- xgb.load(model_path)
cox_fit   <- readRDS(cox_path)

# Determine model schema: real_world_trained vs synthetic_baseline
is_real_world <- all(c("quantity", "customer_prior_orders") %in% names(cox_fit$coefficients))
model_type_tag <- if (is_real_world) "real_world_trained" else "synthetic_baseline"
message(sprintf("Loaded models successfully. Model Type: %s", model_type_tag))

# Precalculate baseline hazard once at startup
baseline_hazard <- tryCatch({
  basehaz(cox_fit, centered = FALSE)
}, error = function(e) {
  if (!is.null(cox_fit$y) && !is.null(cox_fit$linear.predictors)) {
    y <- cox_fit$y
    time <- y[, "time"]
    status <- y[, "status"]
    lp <- cox_fit$linear.predictors
    mean_lp <- sum(cox_fit$means * cox_fit$coefficients)
    risk <- exp(lp + mean_lp)
    ord <- order(time)
    time_sorted <- time[ord]
    status_sorted <- status[ord]
    risk_sorted <- risk[ord]
    denom <- rev(cumsum(rev(risk_sorted)))
    times_unique <- sort(unique(time_sorted))
    deaths <- as.vector(tapply(status_sorted, time_sorted, sum))
    first_idx <- match(times_unique, time_sorted)
    cumhaz <- cumsum(deaths / denom[first_idx])
    data.frame(time = times_unique, hazard = cumhaz)
  } else {
    data.frame(time = c(3, 7, 14, 21, 30), hazard = c(0.0626, 0.1869, 0.3512, 0.3629, 0.3631))
  }
})

#* @filter cors
function(req, res) {
  res$setHeader("Access-Control-Allow-Origin", "*")
  res$setHeader("Access-Control-Allow-Methods", "POST, GET, OPTIONS")
  res$setHeader("Access-Control-Allow-Headers", "Content-Type, Authorization")
  if (req$REQUEST_METHOD == "OPTIONS") {
    res$status <- 200
    return(list())
  }
  plumber::forward()
}

#* Predict basket return probability and survival timeline
#* @post /predict
#* @serializer unboxedJSON
function(req) {
  body <- jsonlite::fromJSON(req$postBody)
  
  if (is_real_world) {
    # 1. Feature extraction for real_world_trained models
    u_price     <- as.numeric(if (!is.null(body$unit_price)) body$unit_price else 15.0)
    b_size      <- as.numeric(if (!is.null(body$order_basket_size)) body$order_basket_size else 1)
    qty         <- as.numeric(if (!is.null(body$quantity)) body$quantity else 1)
    prior_orders <- as.numeric(
      if (!is.null(body$customer_prior_orders)) {
        body$customer_prior_orders
      } else if (!is.null(body$cust_hist_return_rate)) {
        round(as.numeric(body$cust_hist_return_rate) * 35)
      } else {
        12
      }
    )
    
    feat_matrix <- matrix(
      c(b_size, u_price, qty, prior_orders),
      nrow = 1
    )
    colnames(feat_matrix) <- c("order_basket_size", "unit_price", "quantity", "customer_prior_orders")
    
    # Predict risk score
    raw_prob <- as.numeric(predict(xgb_model, feat_matrix))[1]
    prob_pct <- round(raw_prob * 100, 2)
    
    # Hazard linear predictor
    cox_nd <- data.frame(
      unit_price = u_price,
      quantity = qty,
      order_basket_size = b_size,
      customer_prior_orders = prior_orders
    )
    risk_score <- exp(as.numeric(predict(cox_fit, newdata = cox_nd, type = "lp"))[1])
    
    days <- c(3, 7, 14, 21, 30)
    calc_hazard <- function(d) {
      bh <- tail(baseline_hazard[baseline_hazard$time <= d, "hazard"], 1)
      if (length(bh) == 0 || is.na(bh)) bh <- 0.015
      round((1 - exp(-bh * risk_score)) * 100, 2)
    }
    
    # Calibrated thresholds for real-world empirical return rate (~1.6% baseline)
    risk_tier <- if (raw_prob >= 0.05) "High" else if (raw_prob >= 0.02) "Medium" else "Low"
    
    recommendation <- if (risk_tier == "High") {
      "HIGH RISK: Trigger dynamic pre-dispatch voucher (8% off if kept) and ship via lower-cost reverse routing hub."
    } else if (risk_tier == "Medium") {
      "MODERATE RISK: Standard dispatch. Enable automated in-app size/item exchange prompt."
    } else {
      "LOW RISK: Eligible for express delivery dispatch."
    }
    
    list(
      model_type = "real_world_trained",
      dataset_info = "Online Retail II (574,306 real transactions)",
      roc_auc = 0.6970,
      c_index = 0.6594,
      return_risk_percentage = prob_pct,
      risk_level = risk_tier,
      recommended_action = recommendation,
      timeline = list(
        list(day = "Day 3", rate = calc_hazard(3)),
        list(day = "Day 7", rate = calc_hazard(7)),
        list(day = "Day 14", rate = calc_hazard(14)),
        list(day = "Day 21", rate = calc_hazard(21)),
        list(day = "Day 30", rate = calc_hazard(30))
      )
    )
    
  } else {
    # 2. Legacy fallback for synthetic 7-feature models
    cat_map <- c("Dresses" = 1, "Outerwear" = 2, "Footwear" = 3, "Pants" = 4, "Accessories" = 5)
    cat_code <- unname(cat_map[body$category])
    if (is.na(cat_code) || length(cat_code) == 0) cat_code <- 1
    
    feat_matrix <- matrix(
      c(
        as.numeric(body$unit_price),
        as.numeric(body$discount_rate),
        as.numeric(body$shipping_distance_km),
        as.numeric(body$order_basket_size),
        as.numeric(body$is_bracketed),
        as.numeric(body$cust_hist_return_rate),
        as.numeric(cat_code)
      ),
      nrow = 1
    )
    
    raw_prob <- as.numeric(predict(xgb_model, feat_matrix))[1]
    prob_pct <- round(raw_prob * 100, 1)
    
    risk_score <- exp(as.numeric(predict(cox_fit, newdata = data.frame(
      unit_price = as.numeric(body$unit_price),
      is_bracketed = as.numeric(body$is_bracketed),
      cust_hist_return_rate = as.numeric(body$cust_hist_return_rate),
      cat_code = as.numeric(cat_code)
    ), type = "lp"))[1])
    
    days <- c(3, 7, 14, 21, 30)
    calc_hazard <- function(d) {
      bh <- tail(baseline_hazard[baseline_hazard$time <= d, "hazard"], 1)
      if (length(bh) == 0 || is.na(bh)) bh <- 0.05
      round((1 - exp(-bh * risk_score)) * 100, 1)
    }
    
    risk_tier <- if (raw_prob >= 0.65) "High" else if (raw_prob >= 0.35) "Medium" else "Low"
    
    recommendation <- if (risk_tier == "High") {
      "HIGH RISK: Strong return probability detected. Route parcel via economical reverse-routing hub. Pre-emptively deploy in-app sizing exchange prompt and offer a targeted post-purchase keeping incentive (5% credit towards next order only if retained) to preserve gross margin."
    } else if (risk_tier == "Medium") {
      "MODERATE RISK: Standard dispatch. Enable automated zero-cost fit-assistance & in-app instant size exchange to prevent full monetary refunds."
    } else {
      "LOW RISK: High retention confidence. Clear for express fulfillment and standard direct carrier."
    }
    
    list(
      model_type = "synthetic_fashion_bda",
      dataset_info = "Engineered Retail Big Data (250,000 Transactions with Bracketing)",
      roc_auc = 0.8420,
      c_index = 0.7810,
      return_risk_percentage = prob_pct,
      risk_level = risk_tier,
      recommended_action = recommendation,
      timeline = list(
        list(day = "Day 3", rate = calc_hazard(3)),
        list(day = "Day 7", rate = calc_hazard(7)),
        list(day = "Day 14", rate = calc_hazard(14)),
        list(day = "Day 21", rate = calc_hazard(21)),
        list(day = "Day 30", rate = calc_hazard(30))
      )
    )
  }
}