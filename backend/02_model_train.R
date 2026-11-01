# backend/02_model_train.R
# Model training pipeline: XGBoost Classifier + Cox Survival Hazards
library(arrow)
library(data.table)
library(xgboost)
library(survival)

message("Loading Parquet dataset...")
df <- read_parquet("backend/data/processed_orders.parquet")
setDT(df)

cat_map <- c("Dresses" = 1, "Outerwear" = 2, "Footwear" = 3, "Pants" = 4, "Accessories" = 5)
df[, cat_code := cat_map[category]]

feature_cols <- c("unit_price", "discount_rate", "shipping_distance_km", 
                  "order_basket_size", "is_bracketed", "cust_hist_return_rate", "cat_code")

set.seed(42)
train_idx <- sample(seq_len(nrow(df)), size = 0.8 * nrow(df))
train_data <- df[train_idx]
test_data  <- df[-train_idx]

# 1. Train XGBoost
message("Training XGBoost Classifier...")
dtrain <- xgb.DMatrix(data = as.matrix(train_data[, ..feature_cols]), label = train_data$is_returned)
dtest  <- xgb.DMatrix(data = as.matrix(test_data[, ..feature_cols]), label = test_data$is_returned)

params <- list(
  objective = "binary:logistic",
  eval_metric = "auc",
  max_depth = 6,
  eta = 0.1,
  nthread = 4
)

xgb_model <- xgb.train(params, dtrain, nrounds = 80, watchlist = list(eval = dtest), verbose = 0)
xgb.save(xgb_model, "backend/xgb_return_model.model")

# 2. Train Cox Proportional Hazards Model
message("Fitting Cox Proportional Hazards Model...")
sample_cox <- train_data[sample(.N, 50000)]
cox_fit <- coxph(
  Surv(days_to_event, is_returned) ~ unit_price + is_bracketed + cust_hist_return_rate + cat_code,
  data = sample_cox
)

saveRDS(cox_fit, "backend/cox_survival_model.rds")
message("Both models trained and saved to backend/")