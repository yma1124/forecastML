#------------------------------------------------------------------------------
# Test that return_error() works correctly.
library(forecastML)
library(dplyr)

test_that("return_error produces correct mae and mape across aggregations", {

  data("data_seatbelts", package = "forecastML")

  data_seatbelts <- data_seatbelts[, 1:2]

  horizons <- 3
  lookback <- 6

  data_train <- create_lagged_df(data_seatbelts, type = "train", outcome_col = 1,
                                 lookback = lookback, horizons = horizons)

  windows <- create_windows(data_train, window_length = 0)

  data <- data_seatbelts

  model_function <- function(data, my_outcome_col) {

    x <- data[, -(my_outcome_col), drop = FALSE]
    y <- data[, my_outcome_col, drop = FALSE]
    x <- as.matrix(x, ncol = ncol(x))
    y <- as.matrix(y, ncol = ncol(y))

    model <- lm(y ~ x)
    return(model)
  }

  set.seed(224)
  model_results <- train_model(data_train, windows, model_name = "LASSO", model_function,
                               my_outcome_col = 1)

  prediction_function <- function(model, data_features) {

    x <- data_features

    data_pred <- data.frame("y_pred" = predict(model, x))
    return(data_pred)
  }

  # Predict on the validation datasets.
  data_valid <- predict(model_results, prediction_function = list(prediction_function),
                        data = data_train)

  data_valid$DriversKilled <- 10
  data_valid$DriversKilled_pred <- 20

  data_error <- return_error(data_valid)

  data_valid$DriversKilled <- 20
  data_valid$DriversKilled_pred <- 10

  data_error_2 <- return_error(data_valid)

  all(
    all(data_error$error_by_window$mae == 10),
    all(data_error$error_by_horizon$mae == 10),
    all(data_error$error_global$mae == 10),
    all(data_error$error_by_window$mape == 100),
    all(data_error$error_by_horizon$mape == 100),
    all(data_error$error_global$mape == 100),
    all(data_error_2$error_by_window$mape == 50),
    all(data_error_2$error_by_horizon$mape == 50),
    all(data_error_2$error_global$mape == 50)
  )
})
#------------------------------------------------------------------------------
#------------------------------------------------------------------------------
test_that("the rmsse M5 competition metric is correct on validation data with window_length = 0", {

  data("data_seatbelts", package = "forecastML")

  data_seatbelts <- data_seatbelts[, 1:2]

  horizons <- 3
  lookback <- 6

  data_train <- create_lagged_df(data_seatbelts, type = "train", outcome_col = 1,
                                 lookback = lookback, horizons = horizons)

  windows <- create_windows(data_train, window_length = 0)

  data <- data_seatbelts

  model_function <- function(data, my_outcome_col) {

    x <- data[, -(my_outcome_col), drop = FALSE]
    y <- data[, my_outcome_col, drop = FALSE]
    x <- as.matrix(x, ncol = ncol(x))
    y <- as.matrix(y, ncol = ncol(y))

    model <- lm(y ~ x)
    return(model)
  }

  set.seed(224)
  model_results <- train_model(data_train, windows, model_name = "LASSO", model_function,
                               my_outcome_col = 1)

  prediction_function <- function(model, data_features) {

    x <- data_features

    data_pred <- data.frame("y_pred" = predict(model, x))
    return(data_pred)
  }

  # Predict on the validation datasets.
  data_valid <- predict(model_results, prediction_function = list(prediction_function),
                        data = data_train)

  data_results <- data_valid

  sse_num <- sum((data_results$DriversKilled - data_results$DriversKilled_pred)^2, na.rm = TRUE)

  sse_denom <- (1 / (nrow(data_results) - 1)) * sum((data_results$DriversKilled - lag(data_results$DriversKilled, 1))^2, na.rm = TRUE)

  h <- nrow(data_results)

  rmsse <- sqrt((1 / h) * (sse_num / sse_denom))

  data_error <- return_error(data_valid, data_test = data_seatbelts, test_indices = 1:nrow(data_seatbelts))

  all(
    data_error$error_by_window$rmsse == rmsse
  )
})
#------------------------------------------------------------------------------
#------------------------------------------------------------------------------
test_that("the rmsse M5 competition metric is correct for grouped data with multiple validation datasets", {

  data <- data.frame("outcome" = rep(1:10, 2), "group" = rep(1:2, each = 10))

  dates <- rep(seq(as.Date("2019-06-01"), as.Date("2020-03-01"), by = "1 month"), 2)

  lookback <- 1:2
  horizons <- 1:2

  data_train <- create_lagged_df(data, type = "train", outcome_col = 1,
                                 lookback = lookback, horizons = horizons, groups = "group", dates = dates,
                                 frequency = "1 month")

  windows <- create_windows(data_train, window_start = as.Date(c("2020-01-01", "2020-02-01")),
                            window_stop = as.Date(c("2020-01-31", "2020-02-28")))

  model_function <- function(data, my_outcome_col) {

    x <- data[, -(my_outcome_col), drop = FALSE]
    y <- data[, my_outcome_col, drop = FALSE]
    x <- as.matrix(x, ncol = ncol(x))
    y <- as.matrix(y, ncol = ncol(y))

    model <- lm(y ~ x)
    return(model)
  }

  set.seed(224)
  model_results <- train_model(data_train, windows, model_name = "LASSO", model_function,
                               my_outcome_col = 1)

  model <- model_results$horizon_1$window_1$model
  data_features <- data_train$horizon_1

  prediction_function <- function(model, data_features) {

    x <- data_features

    data_pred <- data.frame("y_pred" = 7)
    return(data_pred)
  }

  # Predict on the validation datasets.
  data_valid <- predict(model_results, prediction_function = list(prediction_function),
                        data = data_train)

  data_results <- data_valid

  data_rmsse <- data_results %>%
    dplyr::group_by(.data$model_forecast_horizon, .data$window_number, .data$group) %>%
    dplyr::mutate("residual" = .data$outcome - .data$outcome_pred,
                  "sse_num" = sum(.data$residual^2, na.rm = TRUE))

  data_denom_window_1 <- data
  data_denom_window_1$outcome[data_denom_window_1$outcome %in% c(8, 18)] <- NA
  data_denom_window_2 <- data
  data_denom_window_2$outcome[data_denom_window_2$outcome %in% c(9, 19)] <- NA

  data_denom_window_1 <- data_denom_window_1 %>%
    dplyr::group_by(group) %>%
    dplyr::summarize("mse_denom" = ((1/(7)) * sum((.data$outcome - dplyr::lag(.data$outcome, 1))^2, na.rm = TRUE)))
  data_denom_window_1$window_number <- 1

  data_denom_window_2 <- data_denom_window_2 %>%
    dplyr::group_by(group) %>%
    dplyr::mutate("outcome_lag_1" =  dplyr::lag(.data$outcome, 1),
                  "residual" = .data$outcome - .data$outcome_lag_1,
                  "mse_denom" = ((1/(7)) * sum((.data$outcome - dplyr::lag(.data$outcome, 1))^2, na.rm = TRUE)))
  data_denom_window_2$window_number <- 2

  data_rmsse$mse_denom <- rep(rep(c(1, 1), each = 2), 2)

  h <- 1

  rmsse <- sqrt((1 / 1) * (data_rmsse$sse_num / data_rmsse$mse_denom))

  data_error <- return_error(data_valid, data_test = data, test_indices = dates)

  all(
    data_error$error_by_window$rmsse == rmsse
  )
})
#------------------------------------------------------------------------------
#------------------------------------------------------------------------------

test_that("validation error, window_length = 0 and 1 horizon returns the same error metrics across all aggregations", {

  data("data_seatbelts", package = "forecastML")

  data_seatbelts <- data_seatbelts[, 1:2]

  horizons <- 3
  lookback <- 6

  data_train <- create_lagged_df(data_seatbelts, type = "train", outcome_col = 1,
                                 lookback = lookback, horizons = horizons)

  windows <- create_windows(data_train, window_length = 0)

  model_function <- function(data, my_outcome_col) {

    x <- data[, -(my_outcome_col), drop = FALSE]
    y <- data[, my_outcome_col, drop = FALSE]
    x <- as.matrix(x, ncol = ncol(x))
    y <- as.matrix(y, ncol = ncol(y))

    model <- lm(y ~ x)
    return(model)
  }

  set.seed(224)
  model_results <- train_model(data_train, windows, model_name = "LASSO", model_function,
                               my_outcome_col = 1)

  prediction_function <- function(model, data_features) {

    x <- data_features

    data_pred <- data.frame("y_pred" = predict(model, x))
    return(data_pred)
  }

  # Predict on the validation datasets.
  data_valid <- predict(model_results, prediction_function = list(prediction_function),
                        data = data_train)

  data_error <- return_error(data_valid)

  error_metrics <- c("mae", "mape", "mdape", "smape")

  data_error <- lapply(data_error, function(x) {
    x[, error_metrics]
  })

  expect_mapequal(data_error[[1]], data_error[[2]])
  expect_mapequal(data_error[[1]], data_error[[3]])
  expect_mapequal(data_error[[2]], data_error[[3]])
})
#------------------------------------------------------------------------------
#------------------------------------------------------------------------------

test_that("test/forecast error, 1 horizon returns the 3 data.frames of error metrics", {

  data("data_seatbelts", package = "forecastML")

  data_seatbelts <- data_seatbelts[, 1:2]

  horizons <- 3
  lookback <- 6

  data_train <- create_lagged_df(data_seatbelts, type = "train", outcome_col = 1,
                                 lookback = lookback, horizons = horizons)

  windows <- create_windows(data_train, window_length = 0)

  model_function <- function(data, my_outcome_col) {

    model <- lm(DriversKilled ~ ., data = data)
    return(model)
  }

  set.seed(224)
  model_results <- train_model(data_train, windows, model_name = "LASSO", model_function,
                               my_outcome_col = 1)

  prediction_function <- function(model, data_features) {

    x <- data_features

    data_pred <- data.frame("y_pred" = predict(model, newdata = x))
    return(data_pred)
  }

  data_forecast <- create_lagged_df(data_seatbelts, type = "forecast", outcome_col = 1,
                                    lookback = lookback, horizons = horizons)

  # Forecast
  data_forecasts <- predict(model_results, prediction_function = list(prediction_function),
                            data = data_forecast)

  test_indices <- 192:203
  data_test <- data_seatbelts[test_indices - 11, ]

  data_error <- return_error(data_forecasts, data_test = data_test, test_indices = test_indices, aggregate = mean)

  all(
    nrow(data_error[[1]]) == horizons,
    nrow(data_error[[2]]) == horizons,
    nrow(data_error[[3]]) == 1,
    mean(data_error[[1]]$rmsse) == data_error[[3]]$rmsse
      )
})
#------------------------------------------------------------------------------
#------------------------------------------------------------------------------

test_that("return_error returns correctly when the input is 1 model from combine_forecasts(type = 'horizon')", {

  data("data_seatbelts", package = "forecastML")

  horizons <- c(1, 12)
  lookback <- 1:15

  data_train <- create_lagged_df(data_seatbelts, type = "train", outcome_col = 1,
                                 lookback = lookback, horizon = horizons)

  windows <- create_windows(data_train, window_length = 0)

  model_function <- function(data, my_outcome_col) {
    model <- lm(DriversKilled ~ ., data = data)
    return(model)
  }

  set.seed(224)
  model_results <- train_model(data_train, windows, model_name = "LASSO", model_function)

  data_forecast <- create_lagged_df(data_seatbelts, type = "forecast", outcome_col = 1,
                                    lookback = lookback, horizon = horizons)

  prediction_function <- function(model, data_features) {

    x <- data_features

    data_pred <- data.frame("y_pred" = predict(model, newdata = x))
    return(data_pred)
  }

  data_forecasts <- predict(model_results, prediction_function = list(prediction_function), data = data_forecast)

  data_combined <- combine_forecasts(data_forecasts)

  set.seed(224)
  data_test <- data.frame("DriversKilled" = runif(12, 110, 160), "index" = 193:(193 + 11))
  test_indices <- data_test$index

  data_error_combined <- return_error(data_combined, data_test, test_indices)

  all(
   length(data_error_combined) == 3,
   nrow(data_error_combined[[2]]) == max(horizons)
  )
})

#------------------------------------------------------------------------------
#------------------------------------------------------------------------------

test_that("error metric calculations are correct for combine_forecasts(type = 'horizon')", {

  data("data_seatbelts", package = "forecastML")

  horizons <- c(3, 12)
  lookback <- 1:15

  data_train <- create_lagged_df(data_seatbelts, type = "train", outcome_col = 1,
                                 lookback = lookback, horizon = horizons)

  windows <- create_windows(data_train, window_length = 0)

  historical_mean <- round(mean(data_seatbelts$DriversKilled), 0)

  model_function <- function(data) {
    model <- historical_mean
    return(model)
  }

  set.seed(224)
  model_results <- train_model(data_train, windows, model_name = "mean", model_function)

  data_forecast <- create_lagged_df(data_seatbelts, type = "forecast", outcome_col = 1,
                                    lookback = lookback, horizon = horizons)

  prediction_function <- function(model, data_features) {
    data_pred <- data.frame("y_pred" = model)
    return(data_pred)
  }

  data_forecasts <- predict(model_results, prediction_function = list(prediction_function), data = data_forecast)

  data_combined <- combine_forecasts(data_forecasts)

  set.seed(224)
  data_test <- data.frame("DriversKilled" = runif(12, 110, 160), "index" = 193:(193 + 11))
  test_indices <- data_test$index

  data_error_combined <- return_error(data_combined, data_test, test_indices)

  # Manual calculations
  mae_global <- mean(abs(data_test$DriversKilled - data_combined$DriversKilled_pred))
  rmse_global <- sqrt(mean((data_test$DriversKilled - data_combined$DriversKilled_pred)^2))
  mape_global <- mean(abs(data_test$DriversKilled - data_combined$DriversKilled_pred) / abs(data_test$DriversKilled)) * 100

  # Calculate error by forecast horizon.
  data_error_horizon <- lapply(1:max(horizons), function(i) {

    mae <- mean(abs(data_test$DriversKilled[i] - data_combined$DriversKilled_pred[i]))
    rmse <- sqrt(mean((data_test$DriversKilled[i] - data_combined$DriversKilled_pred[i])^2))
    mape <- mean(abs(data_test$DriversKilled[i] - data_combined$DriversKilled_pred[i]) / abs(data_test$DriversKilled[i])) * 100
    data.frame(mae, rmse, mape)
  })

  data_error_horizon <- dplyr::bind_rows(data_error_horizon)

  all(
    identical(mae_global, data_error_combined$error_global$mae),
    identical(rmse_global, data_error_combined$error_global$rmse),
    identical(mape_global, data_error_combined$error_global$mape),
    identical(data_error_horizon, data_error_combined$error_by_horizon[, c("mae", "rmse", "mape")])
  )
})
#------------------------------------------------------------------------------
#------------------------------------------------------------------------------
