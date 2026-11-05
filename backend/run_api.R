# backend/run_api.R
library(plumber)

port <- as.numeric(Sys.getenv("PORT", unset = 8001))
pr <- plumb("plumber.R")
message(sprintf("Starting Plumber API on 0.0.0.0:%d...", port))
pr$run(host = "0.0.0.0", port = port)