utils::globalVariables(c("truth", "residual", "sensitivity", "specificity"))

#' Summary Function for fastml_model (Using yardstick for ROC Curves)
#'
#' Provides a concise, user-friendly summary of model performances.
#' For classification:
#' - Shows Accuracy, F1 Score, Kappa, Precision, ROC AUC, Sensitivity, Specificity.
#' - Produces a bar plot of these metrics.
#' - Shows ROC curves for binary classification using yardstick::roc_curve().
#' - Displays a confusion matrix and a calibration plot if probabilities are available.
#'
#' For regression:
#' - Shows RMSE, R-squared, and MAE.
#' - Produces a bar plot of these metrics.
#' - Displays residual diagnostics (truth vs predicted, residual distribution).
#'
#'
#' @param object An object of class \code{fastml_model}.
#' @param sort_metric The metric to sort by. Default uses optimized metric.
#' @param plot Logical. If TRUE, produce bar plot, yardstick-based ROC curves (for binary classification),
#'   confusion matrix (classification), smooth calibration plot (if probabilities),
#'   and residual plots (regression).
#' @param combined_roc Logical. If TRUE, combined ROC plot; else separate ROC plots.
#' @param notes User-defined commentary.
#' @param ... Additional arguments.
#' @return Prints summary and plots if requested.
#'
#' @importFrom dplyr filter select mutate bind_rows group_by summarise n
#' @importFrom magrittr %>%
#' @importFrom reshape2 melt dcast
#' @importFrom tune extract_fit_parsnip
#' @importFrom ggplot2 ggplot aes geom_bar geom_path facet_wrap theme_bw theme element_text labs geom_point geom_line geom_histogram geom_abline coord_equal scale_color_manual
#' @importFrom RColorBrewer brewer.pal
#' @importFrom yardstick conf_mat roc_curve
#' @importFrom probably cal_plot_breaks
#' @importFrom rlang get_expr get_env sym
#' @importFrom viridisLite viridis
#'
#' @export
summary.fastml_model <- function(object,
                                 sort_metric = NULL,
                                 plot = TRUE,
                                 combined_roc = TRUE,
                                 notes = "",
                                 ...) {
  if (!inherits(object, "fastml_model")) {
    stop("The input must be a 'fastml_model' object.")
  }

  performance <- object$performance
  predictions_list <- object$predictions
  task <- object$task
  best_model_name <- object$best_model_name
  optimized_metric <- object$metric
  model_count <- length(object$models)

  # Combine performance metrics
  metrics_list <- lapply(names(performance), function(mn) {
    df <- as.data.frame(performance[[mn]])
    df$Model <- mn
    df
  })
  performance_df <- do.call(rbind, metrics_list)

  all_metric_names <- unique(performance_df$.metric)
  if (is.null(sort_metric)) {
    if (optimized_metric %in% all_metric_names) {
      main_metric <- optimized_metric
    } else {
      main_metric <- all_metric_names[1]
      warning("Optimized metric not available; using first metric.")
    }
  } else {
    if (!(sort_metric %in% all_metric_names)) {
      stop("Invalid sort_metric. Available: ", paste(all_metric_names, collapse = ", "))
    }
    main_metric <- sort_metric
  }

  if (task == "classification") {
    desired_metrics <- c("accuracy", "f_meas", "kap", "precision", "sens", "spec", "roc_auc")
  } else {
    desired_metrics <- c("rmse", "rsq", "mae")
  }
  desired_metrics <- intersect(desired_metrics, all_metric_names)
  if (length(desired_metrics) == 0) desired_metrics <- main_metric

  performance_sub <- performance_df[performance_df$.metric %in% desired_metrics, ]
  performance_wide <- dcast(performance_sub, Model ~ .metric, value.var = ".estimate")

  if (task == "regression") {
    performance_wide <- performance_wide[order(performance_wide[[main_metric]], na.last = TRUE), ]
  } else {
    performance_wide <- performance_wide[order(-performance_wide[[main_metric]], na.last = TRUE), ]
  }

  display_names <- c(
    accuracy = "Accuracy",
    f_meas = "F1 Score",
    kap = "Kappa",
    precision = "Precision",
    roc_auc = "ROC AUC",
    sens = "Sensitivity",
    spec = "Specificity",
    rsq = "R-squared",
    mae = "MAE",
    rmse = "RMSE"
  )

  cat("\n===== fastml Model Summary =====\n")
  cat("Task:", task, "\n")
  cat("Number of Models Trained:", model_count, "\n")
  best_val <- performance_wide[performance_wide$Model == best_model_name, main_metric]
  cat("Best Model:", best_model_name, sprintf("(%s: %.3f)", main_metric, best_val), "\n\n")

  cat("Performance Metrics (Sorted by", main_metric, "):\n\n")

  metrics_to_print <- c("Model", desired_metrics)
  best_idx <- which(performance_wide$Model == best_model_name)

  for (m in desired_metrics) {
    performance_wide[[m]] <- format(performance_wide[[m]], digits = 3, nsmall = 3)
  }

  header <- c("Model", sapply(desired_metrics, function(m) {
    if (m %in% names(display_names)) display_names[[m]] else m
  }))

  data_str <- performance_wide
  data_str$Model <- as.character(data_str$Model)
  if (length(best_idx) == 1) data_str$Model[best_idx] <- paste0(data_str$Model[best_idx], "*")

  col_widths <- sapply(seq_along(header), function(i) {
    col_name <- header[i]
    col_data <- data_str[[c("Model", desired_metrics)[i]]]
    max(nchar(col_name), max(nchar(col_data)))
  })

  header_line <- paste(mapply(function(h, w) format(h, width = w, justify = "left"), header, col_widths), collapse = "  ")
  line_sep <- paste(rep("-", sum(col_widths) + 2*(length(col_widths)-1)), collapse = "")

  cat(line_sep, "\n")
  cat(header_line, "\n")
  cat(line_sep, "\n")

  for (i in seq_len(nrow(data_str))) {
    row_line <- paste(mapply(function(v, w) format(v, width = w, justify = "left"),
                             data_str[i, c("Model", desired_metrics), drop=FALSE], col_widths),
                      collapse = "  ")
    cat(row_line, "\n")
  }

  cat(line_sep, "\n")
  cat("(* Best model)\n\n")

  cat("Best Model Hyperparameters:\n\n")
  parsnip_fit <- tryCatch(extract_fit_parsnip(object$best_model), error = function(e) NULL)
  if (is.null(parsnip_fit)) {
    cat("Could not extract final fitted model details.\n")
  } else if ("spec" %in% names(parsnip_fit) && "args" %in% names(parsnip_fit$spec)) {
    params <- parsnip_fit$spec$args
    if (length(params) > 0) {
      cleaned_params <- list()
      for (pname in names(params)) {
        val <- params[[pname]]
        if (inherits(val, "quosure")) {
          val <- tryCatch(eval(get_expr(val), envir = get_env(val)), error = function(e) val)
        }
        cleaned_params[[pname]] <- val
      }
      if (length(cleaned_params) == 0) {
        cat("No hyperparameters found.\n")
      } else {
        for (pname in names(cleaned_params)) {
          val <- cleaned_params[[pname]]
          if (is.numeric(val)) val <- as.character(val)
          cat(pname, ": ", val, "\n", sep = "")
        }
      }
    } else {
      cat("No hyperparameters found.\n")
    }
  } else {
    cat("No hyperparameters found.\n")
  }

  if (nzchar(notes)) {
    cat("\nUser Notes:\n", notes, "\n", sep = "")
  }

  cat("=================================\n")

  if (!plot) return(invisible(object))

  performance_melt <- melt(performance_wide, id.vars = "Model", variable.name = "Metric", value.name = "Value")
  performance_melt <- performance_melt[!is.na(performance_melt$Value), ]
  performance_melt$Value <- as.numeric(performance_melt$Value)
  performance_melt$Metric <- as.character(performance_melt$Metric)
  performance_melt$Metric <- ifelse(
    performance_melt$Metric %in% names(display_names),
    display_names[performance_melt$Metric],
    performance_melt$Metric
  )

  if (task == "classification") {
    class_order <- c("Accuracy", "F1 Score", "Kappa", "Precision", "Sensitivity", "Specificity", "ROC AUC")
    present_class_metrics <- intersect(class_order, unique(performance_melt$Metric))
    if (length(present_class_metrics) > 0) {
      performance_melt$Metric <- factor(performance_melt$Metric, levels = present_class_metrics)
    }
  } else if (task == "regression") {
    reg_order <- c("RMSE", "R-squared", "MAE")
    present_reg_metrics <- intersect(reg_order, unique(performance_melt$Metric))
    if (length(present_reg_metrics) > 0) {
      performance_melt$Metric <- factor(performance_melt$Metric, levels = present_reg_metrics)
    }
  }

  p_bar <- ggplot(performance_melt, aes(x = Model, y = Value, fill = Model)) +
    geom_bar(stat = "identity", position = "dodge") +
    facet_wrap(~ Metric, scales = "free_y") +
    theme_bw() +
    theme(
      axis.text.x = element_text(angle = 45, hjust = 1),
      legend.position = "none"
    ) +
    labs(title = "Model Performance Comparison", x = "Model", y = "Metric Value")

  print(p_bar)

  # ROC curves for binary classification using yardstick
  if (task == "classification" && !is.null(predictions_list) && length(predictions_list) > 0) {
    model_names_pred <- names(predictions_list)
    if (length(model_names_pred) > 0) {
      any_model_name <- model_names_pred[1]
      df_example <- predictions_list[[any_model_name]]
      if (!is.null(df_example) && "truth" %in% names(df_example)) {
        unique_classes <- unique(df_example$truth)
        if (length(unique_classes) == 2) {
          positive_class <- levels(df_example$truth)[1]

          # We'll create a combined data frame for ROC curves from all models
          roc_dfs <- list()
          for (model_name in model_names_pred) {
            df <- predictions_list[[model_name]]
            prob_cols <- grep("^\\.pred_", names(df), value = TRUE)
            if (length(prob_cols) == 2) {
              pred_col <- paste0(".pred_", positive_class)
              if (pred_col %in% prob_cols) {
                roc_df <- roc_curve(df, truth, !!sym(pred_col))
                roc_df$Model <- model_name
                roc_dfs[[model_name]] <- roc_df
              }
            }
          }

          if (length(roc_dfs) > 0) {
            all_roc <- bind_rows(roc_dfs)

            num_curves <- length(roc_dfs)
            if (num_curves > 1) {
              # Generate a sequence of pretty colors with viridis
              colors <- viridis(num_curves)
            } else {
              # If there's only one curve, just use black or any single color
              colors <- "#000000"
            }
            if (combined_roc) {
              p_roc <- ggplot(all_roc, aes(x = 1 - specificity, y = sensitivity, color = Model)) +
                geom_path() +
                geom_abline(lty = 3) +
                coord_equal() +
                theme_bw() +
                labs(title = "Combined ROC Curves for All Models") +
                scale_color_manual(values = colors)
              print(p_roc)
            } else {
              # Separate plots for each model
              # We'll just facet by Model
              p_roc_sep <- ggplot(all_roc, aes(x = 1 - specificity, y = sensitivity, color = Model)) +
                geom_path() +
                geom_abline(lty = 3) +
                coord_equal() +
                facet_wrap(~ Model) +
                theme_bw() +
                labs(title = "ROC Curves by Model") +
                scale_color_manual(values = colors) +
                theme(legend.position = "none")
              print(p_roc_sep)
            }
          } else {
            cat("\nNo suitable probability predictions for ROC curves.\n")
          }

        } else {
          cat("\nROC curves are only generated for binary classification tasks.\n")
        }
      } else {
        cat("\nNo predictions available to generate ROC curves.\n")
      }
    } else {
      cat("\nNo predictions available to generate ROC curves.\n")
    }
  }

  # Additional Diagnostics
  if (plot && !is.null(predictions_list) && best_model_name %in% names(predictions_list)) {
    df_best <- predictions_list[[best_model_name]]
    if (task == "classification") {
      if (!is.null(df_best) && "truth" %in% names(df_best) && "estimate" %in% names(df_best)) {
        cm <- conf_mat(df_best, truth = truth, estimate = estimate)
        cat("\nConfusion Matrix for Best Model:\n")
        print(cm)

        # Calibration Plot
        if (requireNamespace("probably", quietly = TRUE)) {
          prob_cols <- grep("^\\.pred_", names(df_best), value = TRUE)
          if (length(prob_cols) > 1) {
            positive_class <- levels(df_best$truth)[1]
            pred_col <- paste0(".pred_", positive_class)
            if (pred_col %in% prob_cols) {
              p_cal <- cal_plot_breaks(df_best, truth = truth, estimate = !!sym(pred_col)) +
                labs(title = "Calibration Plot")
              print(p_cal)
            }
          }
        } else {
          cat("\nInstall the 'probably' package for a calibration plot.\n")
        }
      }
    } else if (task == "regression") {
      if (!is.null(df_best) && "truth" %in% names(df_best) && "estimate" %in% names(df_best)) {
        df_best <- df_best %>% mutate(residual = truth - estimate)
        cat("\nResidual Diagnostics for Best Model:\n")

        p_truth_pred <- ggplot(df_best, aes(x = estimate, y = truth)) +
          geom_point(alpha = 0.6) +
          geom_abline(linetype = "dashed", color = "red") +
          labs(title = "Truth vs Predicted", x = "Predicted", y = "Truth") +
          theme_bw()

        print(p_truth_pred)

        p_resid_hist <- ggplot(df_best, aes(x = residual)) +
          geom_histogram(bins = 30, fill = "steelblue", color = "white", alpha = 0.7) +
          labs(title = "Residual Distribution", x = "Residual", y = "Count") +
          theme_bw()

        print(p_resid_hist)
      }
    }
  }

  invisible(object)
}
