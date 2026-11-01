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
#* @serializer json
function(req) {
  body <- jsonlite::fromJSON(req$postBody)
  
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
  
  # Predict risk score as a clean numeric scalar
  raw_prob <- as.numeric(predict(xgb_model, feat_matrix))[1]
  prob_pct <- round(raw_prob * 100, 1)
  
  # Hazard baseline estimation
  baseline_hazard <- basehaz(cox_fit, centered = FALSE)
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
  
  recommendation <- if (raw_prob > 0.65) {
    "HIGH RISK: Trigger dynamic pre-dispatch voucher (8% off if kept) and ship via lower-cost reverse routing hub."
  } else if (raw_prob > 0.35) {
    "MODERATE RISK: Standard dispatch. Enable automated in-app size exchange prompt."
  } else {
    "LOW RISK: Eligible for express delivery dispatch."
  }
  
  list(
    return_risk_percentage = prob_pct,
    risk_level = if (raw_prob > 0.65) "High" else if (raw_prob > 0.35) "Medium" else "Low",
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