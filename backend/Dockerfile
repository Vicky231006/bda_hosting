# backend/Dockerfile
FROM rocker/r-ver:4.3.2

# Install Linux system dependencies needed for Arrow and R packages
RUN apt-get update -qq && apt-get install -y --no-install-recommends \
    libcurl4-openssl-dev \
    libssl-dev \
    libxml2-dev \
    libsodium-dev \
    git \
    && rm -rf /var/lib/apt/lists/*

# Install required R packages
RUN R -e "install.packages(c('plumber', 'xgboost', 'survival', 'jsonlite', 'data.table', 'arrow'), repos='https://cloud.r-project.org/')"

WORKDIR /app

# Copy model artifacts and API scripts
COPY xgb_return_model.model /app/xgb_return_model.model
COPY cox_survival_model.rds /app/cox_survival_model.rds
COPY plumber.R /app/plumber.R
COPY run_api.R /app/run_api.R

# Port exposure
EXPOSE 8000

# Start Plumber
CMD ["Rscript", "run_api.R"]