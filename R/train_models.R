utils::globalVariables("if_else")

#' Train Specified Machine Learning Algorithms on the Training Data
#'
#' Trains specified machine learning algorithms on the preprocessed training data.
#'
#' @param train_data Preprocessed training data frame.
#' @param label Name of the target variable.
#' @param task Type of task: "classification" or "regression".
#' @param algorithms Vector of algorithm names to train.
#' @param resampling_method Resampling method for cross-validation (e.g., "cv", "repeatedcv", "boot", "none").
#' @param folds Number of folds for cross-validation.
#' @param repeats Number of times to repeat cross-validation (only applicable for methods like "repeatedcv").
#' @param tune_params List of hyperparameter tuning ranges.
#' @param metric The performance metric to optimize.
#' @param summaryFunction A custom summary function for model evaluation. Default is \code{NULL}.
#' @param seed An integer value specifying the random seed for reproducibility.
#' @param recipe A recipe object for preprocessing.
#' @param use_default_tuning Logical indicating whether to use default tuning grids when \code{tune_params} is \code{NULL}. Default is \code{FALSE}.
#' @importFrom magrittr %>%
#' @importFrom dplyr filter mutate select
#' @importFrom tibble tibble
#' @importFrom rlang sym
#' @importFrom dials range_set value_set grid_regular grid_latin_hypercube finalize
#' @importFrom parsnip fit extract_parameter_set_dials
#' @importFrom workflows workflow add_model add_recipe
#' @importFrom tune tune_grid control_grid select_best finalize_workflow finalize_model
#' @importFrom yardstick metric_set accuracy kap roc_auc sens spec precision f_meas rmse rsq mae
#' @importFrom rsample vfold_cv bootstraps validation_split
#' @importFrom recipes all_nominal_predictors all_numeric_predictors all_outcomes all_predictors
#' @return A list of trained model objects.
#' @export

train_models <- function(train_data,
                         label,
                         task,
                         algorithms,
                         resampling_method,
                         folds,
                         repeats,
                         tune_params,
                         metric,
                         summaryFunction = NULL,
                         seed = 123,
                         recipe,
                         use_default_tuning = FALSE) {

  # Set random seed
  set.seed(seed)

  # Decide on metrics
  if (task == "classification") {
    metrics <- metric_set(
      accuracy,
      kap,
      sens,
      spec,
      precision,
      f_meas,
      roc_auc
    )
  } else {
    metrics <- metric_set(rmse, rsq, mae)
  }

  # Set up resampling
  if (resampling_method == "cv") {
    resamples <- vfold_cv(train_data, v = folds, repeats = 1, strata = if (task == "classification") all_of(label) else NULL)
  } else if (resampling_method == "boot") {
    resamples <- bootstraps(train_data, times = folds, strata = if (task == "classification") all_of(label) else NULL)
  } else if (resampling_method == "repeatedcv") {
    resamples <- vfold_cv(train_data, v = folds, repeats = repeats, strata = if (task == "classification") all_of(label) else NULL)
  } else if (resampling_method == "none") {
    resamples <- NULL
  } else {
    stop("Unsupported resampling method.")
  }

  # Initialize models list
  models <- list()

  # Helper function to update parameters
  update_params <- function(params_model, new_params) {
    for (param_name in names(new_params)) {
      param_value <- new_params[[param_name]]

      # Locate the parameter in the parameter set
      param_row <- params_model %>% filter(id == param_name)
      if (nrow(param_row) == 0) {
        next  # Parameter not found, skip to the next one
      }

      # Get the parameter object
      param_obj <- param_row$object[[1]]

      if (length(param_value) == 2) {
        # It's a range; ensure the type matches
        if (inherits(param_obj, "integer_parameter")) {
          param_obj <- param_obj %>% range_set(c(as.integer(param_value[1]), as.integer(param_value[2])))
        } else {
          param_obj <- param_obj %>% range_set(param_value)
        }
      } else {
        # Single value or vector of values; set value_set
        if (inherits(param_obj, "integer_parameter")) {
          param_obj <- param_obj %>% value_set(as.integer(param_value))
        } else {
          param_obj <- param_obj %>% value_set(param_value)
        }
      }

      # Update the parameter in the parameter set
      params_model <- params_model %>%
        mutate(object = if_else(id == param_name, list(param_obj), object))
    }
    return(params_model)
  }

  # Loop over each algorithm
  for (algo in algorithms) {
    set.seed(seed)
    model <- NULL

    # Determine if tuning parameters are provided for this algorithm
    algo_tune_params <- if (!is.null(tune_params)) tune_params[[algo]] else NULL

    # If tune_params is NULL and use_default_tuning is TRUE, get default tuning parameters
    if (is.null(algo_tune_params) && use_default_tuning) {
      algo_tune_params <- get_default_tune_params(algo, train_data, label)
    }

    # Determine if tuning will be performed
    perform_tuning <- !is.null(algo_tune_params) && !is.null(resamples)

    # Define model specification and tuning grid
    model_info <- switch(algo,
                         "random_forest" = define_random_forest_spec(task, train_data, label, tune = perform_tuning),
                         "ranger" = define_ranger_spec(task, train_data, label, tune = perform_tuning),
                         "c5.0" = define_c5_0_spec(task, tune = perform_tuning),
                         "xgboost" = define_xgboost_spec(task, train_data, label, tune = perform_tuning),
                         "lightgbm" = define_lightgbm_spec(task, train_data, label, tune = perform_tuning),
                         "logistic_regression" = define_logistic_regression_spec(task, tune = perform_tuning),
                         "penalized_logistic_regression" = define_penalized_logistic_regression_spec(task, tune = perform_tuning),
                         "decision_tree" = define_decision_tree_spec(task, tune = perform_tuning),
                         "svm_linear" = define_svm_linear_spec(task, tune = perform_tuning),
                         "svm_radial" = define_svm_radial_spec(task, tune = perform_tuning),
                         "knn" = define_knn_spec(task, tune = perform_tuning),
                         "naive_bayes" = define_naive_bayes_spec(task, tune = perform_tuning),
                         "neural_network" = define_neural_network_spec(task, tune = perform_tuning),
                         "deep_learning" = define_deep_learning_spec(task, tune = perform_tuning),
                         "lda" = define_lda_spec(task),
                         "qda" = define_qda_spec(task),
                         "bagging" = define_bagging_spec(task, tune = perform_tuning),
                         "elastic_net" = define_elastic_net_spec(task, tune = perform_tuning),
                         "bayes_glm" = define_bayes_glm_spec(task),
                         "pls" = define_pls_spec(task, tune = perform_tuning),
                         "linear_regression" = define_linear_regression_spec(task),
                         "ridge_regression" = define_ridge_regression_spec(task, tune = perform_tuning),
                         "lasso_regression" = define_lasso_regression_spec(task, tune = perform_tuning),
                         {
                           warning(paste("Algorithm", algo, "is not supported or failed to train."))
                           next
                         })
    model_spec <- model_info$model_spec

    # Obtain tunable parameters
    if (perform_tuning) {
      tune_params_model <- extract_parameter_set_dials(model_spec)

      # Finalize parameters that depend on the data
      tune_params_model <- finalize(
        tune_params_model,
        x = train_data %>% select(-all_of(label))
      )

      # Update parameter ranges with user-provided tune_params
      if (!is.null(algo_tune_params)) {
        tune_params_model <- update_params(tune_params_model, algo_tune_params)
      }

      # Now create the tuning grid
      if (nrow(tune_params_model) > 0) {
        # For parameters on log scale, use grid_latin_hypercube
        if (any(sapply(tune_params_model$object, function(x) {
          if (!is.null(x$trans) && !is.null(x$trans$value)) {
            x$trans$value %in% c("log2", "log10", "log", "ln")
          } else {
            FALSE
          }
        }))) {
          tune_grid <- grid_latin_hypercube(
            tune_params_model,
            size = 10
          )
        } else {
          tune_grid <- grid_regular(
            tune_params_model,
            levels = 3  # Adjust levels for efficiency
          )
        }
      } else {
        # No tunable parameters
        tune_grid <- NULL
      }
    } else {
      tune_grid <- NULL
    }

    # Create a workflow
    workflow <- workflow() %>%
      add_model(model_spec) %>%
      add_recipe(recipe)

    # Perform tuning or fit the model directly if no tuning parameters
    tryCatch({
      if (!is.null(tune_grid)) {
        if (!is.null(resamples)) {
          # Perform tuning using resamples
          model_tuned <- tune_grid(
            workflow,
            resamples = resamples,
            grid = tune_grid,
            metrics = metrics,
            control = control_grid(save_pred = TRUE)
          )
          # Finalize the workflow with the best parameters
          best_params <- select_best(model_tuned, metric = metric)
          final_workflow <- finalize_workflow(workflow, best_params)
          # Fit the final model on the entire training data
          model <- fit(final_workflow, data = train_data)
        } else {
          # This block should not be reached because tune_grid is NULL when resamples is NULL
          stop("Tuning cannot be performed without resamples.")
        }
      } else {
        # No tuning parameters, fit the model directly
        model <- fit(workflow, data = train_data)
      }
      models[[algo]] <- model
    }, error = function(e) {
      warning(paste(
        "Training failed for algorithm:",
        algo,
        "\nError message:",
        e$message
      ))
    })
  }

  if (length(models) == 0) {
    stop("No models were successfully trained. Please check your data and parameters.")
  }

  return(models)
}


# Declare global variables
utils::globalVariables(c(
  "id", "object", "estimate", ".metric", ".estimate", ".pred", ".pred_class",
  "rmse", "rsq", "min_n", "num_comp"
))

# Central repository for default parameters
get_default_params <- function(algo, num_predictors = NULL) {
  switch(algo,
         # 1. Random Forest
         "random_forest" = list(
           mtry = if (!is.null(num_predictors)) max(1, floor(sqrt(num_predictors))) else 2,
           trees = 100,
           min_n = 5
         ),
         # 2. Ranger (same as Random Forest)
         "ranger" = list(
           mtry = if (!is.null(num_predictors)) max(1, floor(sqrt(num_predictors))) else 2,
           trees = 100,
           min_n = 5
         ),
         # 4. C5.0
         "c5.0" = list(
           trees = 50,
           min_n = 5,
           sample_size = 0.5
         ),
         # 5. XGBoost
         "xgboost" = list(
           trees = 100,
           tree_depth = 3,
           learn_rate = 0.1,
           loss_reduction = 0,
           min_n = 5,
           sample_size = 1,
           mtry = if (!is.null(num_predictors)) max(1, floor(sqrt(num_predictors))) else 2
         ),
         # 6. LightGBM
         "lightgbm" = list(
           trees = 100,
           tree_depth = 3,
           learn_rate = 0.1,
           loss_reduction = 0,
           min_n = 5,
           sample_size = 1,
           mtry = if (!is.null(num_predictors)) max(1, floor(sqrt(num_predictors))) else 2
         ),
         # 7. Logistic Regression
         "logistic_regression" = list(),
         # 8. Penalized Logistic Regression
         "penalized_logistic_regression" = list(
           penalty = 0.01,
           mixture = 0.5
         ),
         # 9. Decision Tree
         "decision_tree" = list(
           cost_complexity = 0.01,
           tree_depth = 5,
           min_n = 5
         ),
         # 10. SVM Linear
         "svm_linear" = list(
           cost = 1
         ),
         # 11. SVM Radial
         "svm_radial" = list(
           cost = 1,
           rbf_sigma = 0.1
         ),
         # 12. KNN
         "knn" = list(
           neighbors = 5,
           weight_func = "rectangular",
           dist_power = 2
         ),
         # 13. Naive Bayes
         "naive_bayes" = list(
           smoothness = 1,
           Laplace = 0
         ),
         # 14. Neural Network (nnet)
         "neural_network" = list(
           hidden_units = 5,
           penalty = 0.01,
           epochs = 100
         ),
         # 15. Deep Learning (keras)
         "deep_learning" = list(
           hidden_units = 10,
           penalty = 0.001,
           epochs = 50
         ),
         # 16. LDA
         "lda" = list(),
         # 17. QDA
         "qda" = list(),
         # 18. Bagging
         "bagging" = list(
           min_n = 5
         ),
         # 19. Elastic Net
         "elastic_net" = list(
           penalty = 0.01,
           mixture = 0.5
         ),
         # 20. Bayesian GLM
         "bayes_glm" = list(),
         # 21. PLS
         "pls" = list(
           num_comp = 2
         ),
         # 22. Linear Regression
         "linear_regression" = list(),
         # 23. Ridge Regression
         "ridge_regression" = list(
           penalty = 0.01,
           mixture = 0
         ),
         # 24. Lasso Regression
         "lasso_regression" = list(
           penalty = 0.01,
           mixture = 1
         ),
         NULL)
}

# Function to get default tuning parameters
# Function to get default tuning parameters
get_default_tune_params <- function(algo, train_data, label) {
  # Determine the number of predictors
  num_predictors <- ncol(train_data %>% select(-!!sym(label)))

  switch(algo,
         # 1. Random Forest
         "random_forest" = list(
           mtry = c(1, max(1, floor(sqrt(num_predictors)))),
           trees = c(100, 200),  # Reduced upper limit for efficiency
           min_n = c(2, 5)
         ),

         # 2. Ranger (same as Random Forest)
         "ranger" = list(
           mtry = c(1, max(1, floor(sqrt(num_predictors)))),
           trees = c(100, 200),
           min_n = c(2, 5)
         ),

         # 4. C5.0
         "c5.0" = list(
           trees = c(1, 50),  # Reduced upper limit for efficiency
           min_n = c(2, 5)
         ),

         # 5. XGBoost
         "xgboost" = list(
           trees = c(50, 150),  # Reduced range for efficiency
           tree_depth = c(1, 5),  # Reduced maximum depth
           learn_rate = c(-2, -1),  # log scale
           loss_reduction = c(0, 5),  # Reduced upper limit
           min_n = c(2, 5),
           sample_size = c(0.5, 1),
           mtry = c(1, num_predictors)
         ),

         # 6. LightGBM
         "lightgbm" = list(
           trees = c(50, 150),  # Reduced range for efficiency
           tree_depth = c(1, 5),  # Reduced maximum depth
           learn_rate = c(-2, -1),  # log scale
           loss_reduction = c(0, 5),  # Reduced upper limit
           min_n = c(2, 5),
           sample_size = c(0.5, 1),
           mtry = c(1, num_predictors)
         ),

         # 7. Logistic Regression
         "logistic_regression" = list(
           penalty = c(-5, 0),  # log scale
           mixture = c(0, 1)
         ),

         # 8. Penalized Logistic Regression
         "penalized_logistic_regression" = list(
           penalty = c(-5, 0),  # log scale
           mixture = c(0, 1)
         ),

         # 9. Decision Tree
         "decision_tree" = list(
           cost_complexity = c(-5, 0),  # log scale
           tree_depth = c(1, 5),  # Reduced maximum depth
           min_n = c(2, 5)
         ),

         # 10. SVM Linear
         "svm_linear" = list(
           cost = c(-3, 3)  # log scale
         ),

         # 11. SVM Radial
         "svm_radial" = list(
           cost = c(-3, 3),  # log scale
           rbf_sigma = c(-9, -1)  # log scale
         ),

         # 12. KNN
         "knn" = list(
           neighbors = c(3, 7),  # Narrowed range for efficiency
           weight_func = c("rectangular", "triangular"),
           dist_power = c(1, 2)
         ),

         # 13. Naive Bayes
         "naive_bayes" = list(
           smoothness = c(0, 1),
           Laplace = c(0, 1)
         ),

         # 14. Neural Network (nnet)
         "neural_network" = list(
           hidden_units = c(1, 5),  # Reduced upper limit
           penalty = c(-5, -1),  # log scale
           epochs = c(100, 150)  # Reduced upper limit
         ),

         # 15. Deep Learning (keras)
         "deep_learning" = list(
           hidden_units = c(10, 30),  # Reduced upper limit
           penalty = c(-5, -1),  # log scale
           epochs = c(50, 100)  # Reduced upper limit
         ),

         # 16. LDA
         "lda" = NULL,

         # 17. QDA
         "qda" = NULL,

         # 18. Bagging
         "bagging" = list(
           cost_complexity = c(-5, 0),  # log scale
           tree_depth = c(1, 5),  # Reduced maximum depth
           min_n = c(2, 5)
         ),

         # 19. Elastic Net
         "elastic_net" = list(
           penalty = c(-5, 0),  # log scale
           mixture = c(0, 1)
         ),

         # 20. Bayesian GLM
         "bayes_glm" = NULL,

         # 21. PLS
         "pls" = list(
           num_comp = c(1, min(5, num_predictors))  # Reduced upper limit
         ),

         # 22. Linear Regression
         "linear_regression" = NULL,

         # 23. Ridge Regression
         "ridge_regression" = list(
           penalty = c(-5, 0)  # log scale
         ),

         # 24. Lasso Regression
         "lasso_regression" = list(
           penalty = c(-5, 0)  # log scale
         ),

         # Default case
         NULL)
}


# Define algorithm specification functions

#' Define Random Forest Model Specification
#'
#' @param task Character string specifying the task type: "classification" or "regression".
#' @param train_data Data frame containing the training data.
#' @param label Character string specifying the name of the target variable.
#' @param tune Logical indicating whether to use tuning parameters.
#' @return List containing the model specification (`model_spec`).
#' @importFrom parsnip rand_forest set_mode set_engine
#' @importFrom dplyr select all_of
define_random_forest_spec <- function(task, train_data, label, tune = FALSE) {
  num_predictors <- ncol(train_data %>% select(-all_of(label)))
  defaults <- get_default_params("random_forest", num_predictors)

  if (tune) {
    model_spec <- rand_forest(
      mtry = tune(),
      trees = tune(),
      min_n = tune()
    ) %>%
      set_mode(task) %>%
      set_engine("ranger")
  } else {
    model_spec <- rand_forest(
      mtry = defaults$mtry,
      trees = defaults$trees,
      min_n = defaults$min_n
    ) %>%
      set_mode(task) %>%
      set_engine("ranger")
  }
  list(model_spec = model_spec)
}

#' Define Ranger Model Specification
#'
#' @inheritParams define_random_forest_spec
#' @return List containing the model specification (`model_spec`).
define_ranger_spec <- function(task, train_data, label, tune = FALSE) {
  define_random_forest_spec(task, train_data, label, tune)
}


#' Define C5.0 Model Specification
#'
#' @inheritParams define_random_forest_spec
#' @return List containing the model specification (`model_spec`).
#' @importFrom parsnip boost_tree set_mode set_engine
define_c5_0_spec <- function(task, tune = FALSE) {
  if (task != "classification") {
    stop("C5.0 is only applicable for classification tasks.")
  }
  defaults <- get_default_params("c5.0")

  if (tune) {
    model_spec <- boost_tree(
      trees = tune(),
      min_n = tune(),
      sample_size = tune()
    ) %>%
      set_mode("classification") %>%
      set_engine("C5.0")
  } else {
    model_spec <- boost_tree(
      trees = defaults$trees,
      min_n = defaults$min_n,
      sample_size = defaults$sample_size
    ) %>%
      set_mode("classification") %>%
      set_engine("C5.0")
  }
  list(model_spec = model_spec)
}

#' Define XGBoost Model Specification
#'
#' @inheritParams define_random_forest_spec
#' @return List containing the model specification (`model_spec`).
#' @importFrom parsnip boost_tree set_mode set_engine
define_xgboost_spec <- function(task, train_data, label, tune = FALSE) {
  num_predictors <- ncol(train_data %>% select(-all_of(label)))
  defaults <- get_default_params("xgboost", num_predictors)

  if (tune) {
    model_spec <- boost_tree(
      trees = tune(),
      tree_depth = tune(),
      learn_rate = tune(),
      mtry = tune(),
      min_n = tune(),
      loss_reduction = tune(),
      sample_size = tune()
    ) %>%
      set_mode(task) %>%
      set_engine("xgboost")
  } else {
    model_spec <- boost_tree(
      trees = defaults$trees,
      tree_depth = defaults$tree_depth,
      learn_rate = defaults$learn_rate,
      mtry = defaults$mtry,
      min_n = defaults$min_n,
      loss_reduction = defaults$loss_reduction,
      sample_size = defaults$sample_size
    ) %>%
      set_mode(task) %>%
      set_engine("xgboost")
  }
  list(model_spec = model_spec)
}

#' Define LightGBM Model Specification
#'
#' @inheritParams define_random_forest_spec
#' @return List containing the model specification (`model_spec`).
#' @importFrom parsnip boost_tree set_mode set_engine
define_lightgbm_spec <- function(task, train_data, label, tune = FALSE) {
  if (!requireNamespace("lightgbm", quietly = TRUE)) {
    stop("The 'lightgbm' package is required but is not installed.")
  }
  num_predictors <- ncol(train_data %>% select(-all_of(label)))
  defaults <- get_default_params("lightgbm", num_predictors)

  if (tune) {
    model_spec <- boost_tree(
      trees = tune(),
      tree_depth = tune(),
      learn_rate = tune(),
      mtry = tune(),
      min_n = tune(),
      loss_reduction = tune(),
      sample_size = tune()
    ) %>%
      set_mode(task) %>%
      set_engine("lightgbm")
  } else {
    model_spec <- boost_tree(
      trees = defaults$trees,
      tree_depth = defaults$tree_depth,
      learn_rate = defaults$learn_rate,
      mtry = defaults$mtry,
      min_n = defaults$min_n,
      loss_reduction = defaults$loss_reduction,
      sample_size = defaults$sample_size
    ) %>%
      set_mode(task) %>%
      set_engine("lightgbm")
  }
  list(model_spec = model_spec)
}

#' Define Logistic Regression Model Specification
#'
#' @param task Character string specifying the task type ("classification").
#' @inheritParams define_random_forest_spec
#' @return List containing the model specification (`model_spec`).
#' @importFrom parsnip logistic_reg set_mode set_engine
define_logistic_regression_spec <- function(task, tune = FALSE) {
  if (task != "classification") {
    stop("Logistic regression is only applicable for classification tasks.")
  }
  if (tune) {
    model_spec <- logistic_reg(
      penalty = tune()
    ) %>%
      set_mode("classification") %>%
      set_engine("glmnet")
  } else {
    model_spec <- logistic_reg() %>%
      set_mode("classification") %>%
      set_engine("glm")
  }
  list(model_spec = model_spec)
}

#' Define Penalized Logistic Regression Model Specification
#'
#' @inheritParams define_logistic_regression_spec
#' @return List containing the model specification (`model_spec`).
#' @importFrom parsnip logistic_reg set_engine
#' @importFrom tune finalize_model
define_penalized_logistic_regression_spec <- function(task, tune = FALSE) {
  if (task != "classification") {
    stop("Penalized logistic regression is only applicable for classification tasks.")
  }
  defaults <- get_default_params("penalized_logistic_regression")

  if (tune) {
    model_spec <- logistic_reg(
      penalty = tune(),
      mixture = tune()
    ) %>%
      set_engine("glmnet")
  } else {
    model_spec <- logistic_reg(
      penalty = defaults$penalty,
      mixture = defaults$mixture
    ) %>%
      set_engine("glmnet")
    model_spec <- finalize_model(model_spec, parameters = tibble())
  }
  list(model_spec = model_spec)
}

#' Define Decision Tree Model Specification
#'
#' @inheritParams define_random_forest_spec
#' @return List containing the model specification (`model_spec`).
#' @importFrom parsnip decision_tree set_mode set_engine
define_decision_tree_spec <- function(task, tune = FALSE) {
  defaults <- get_default_params("decision_tree")

  if (tune) {
    model_spec <- decision_tree(
      tree_depth = tune(),
      min_n = tune(),
      cost_complexity = tune()
    ) %>%
      set_mode(task) %>%
      set_engine("rpart")
  } else {
    model_spec <- decision_tree(
      tree_depth = defaults$tree_depth,
      min_n = defaults$min_n,
      cost_complexity = defaults$cost_complexity
    ) %>%
      set_mode(task) %>%
      set_engine("rpart")
  }
  list(model_spec = model_spec)
}

#' Define SVM Linear Model Specification
#'
#' @inheritParams define_random_forest_spec
#' @return List containing the model specification (`model_spec`).
#' @importFrom parsnip svm_linear set_mode set_engine
define_svm_linear_spec <- function(task, tune = FALSE) {
  defaults <- get_default_params("svm_linear")

  if (tune) {
    model_spec <- svm_linear(
      cost = tune()
    ) %>%
      set_mode(task) %>%
      set_engine("kernlab")
  } else {
    model_spec <- svm_linear(
      cost = defaults$cost
    ) %>%
      set_mode(task) %>%
      set_engine("kernlab")
  }
  list(model_spec = model_spec)
}

#' Define SVM Radial Model Specification
#'
#' @inheritParams define_svm_linear_spec
#' @return List containing the model specification (`model_spec`).
#' @importFrom parsnip svm_rbf set_mode set_engine
define_svm_radial_spec <- function(task, tune = FALSE) {
  defaults <- get_default_params("svm_radial")

  if (tune) {
    model_spec <- svm_rbf(
      cost = tune(),
      rbf_sigma = tune()
    ) %>%
      set_mode(task) %>%
      set_engine("kernlab")
  } else {
    model_spec <- svm_rbf(
      cost = defaults$cost,
      rbf_sigma = defaults$rbf_sigma
    ) %>%
      set_mode(task) %>%
      set_engine("kernlab")
  }
  list(model_spec = model_spec)
}

#' Define K-Nearest Neighbors Model Specification
#'
#' @inheritParams define_random_forest_spec
#' @return List containing the model specification (`model_spec`).
#' @importFrom parsnip nearest_neighbor set_mode set_engine
define_knn_spec <- function(task, tune = FALSE) {
  defaults <- get_default_params("knn")

  if (tune) {
    model_spec <- nearest_neighbor(
      neighbors = tune(),
      weight_func = tune(),
      dist_power = tune()
    ) %>%
      set_mode(task) %>%
      set_engine("kknn")
  } else {
    model_spec <- nearest_neighbor(
      neighbors = defaults$neighbors,
      weight_func = defaults$weight_func,
      dist_power = defaults$dist_power
    ) %>%
      set_mode(task) %>%
      set_engine("kknn")
  }
  list(model_spec = model_spec)
}

#' Define Naive Bayes Model Specification
#'
#' @inheritParams define_logistic_regression_spec
#' @return List containing the model specification (`model_spec`).
#' @importFrom parsnip naive_Bayes set_mode set_engine
define_naive_bayes_spec <- function(task, tune = FALSE) {
  if (task != "classification") {
    stop("Naive Bayes is only applicable for classification tasks.")
  }
  defaults <- get_default_params("naive_bayes")

  if (tune) {
    model_spec <- naive_Bayes(
      smoothness = tune(),
      Laplace = tune()
    ) %>%
      set_mode("classification") %>%
      set_engine("klaR")
  } else {
    model_spec <- naive_Bayes(
      smoothness = defaults$smoothness,
      Laplace = defaults$Laplace
    ) %>%
      set_mode("classification") %>%
      set_engine("klaR")
  }
  list(model_spec = model_spec)
}

#' Define Neural Network Model Specification (nnet)
#'
#' @inheritParams define_random_forest_spec
#' @return List containing the model specification (`model_spec`).
#' @importFrom parsnip mlp set_mode set_engine
define_neural_network_spec <- function(task, tune = FALSE) {
  defaults <- get_default_params("neural_network")

  if (tune) {
    model_spec <- mlp(
      hidden_units = tune(),
      penalty = tune(),
      epochs = tune()
    ) %>%
      set_mode(task) %>%
      set_engine("nnet")
  } else {
    model_spec <- mlp(
      hidden_units = defaults$hidden_units,
      penalty = defaults$penalty,
      epochs = defaults$epochs
    ) %>%
      set_mode(task) %>%
      set_engine("nnet")
  }
  list(model_spec = model_spec)
}

#' Define Deep Learning Model Specification (keras)
#'
#' @inheritParams define_neural_network_spec
#' @return List containing the model specification (`model_spec`).
#' @importFrom parsnip mlp set_mode set_engine
define_deep_learning_spec <- function(task, tune = FALSE) {
  if (!requireNamespace("keras", quietly = TRUE)) {
    stop("The 'keras' package is required for deep learning but is not installed.")
  }
  defaults <- get_default_params("deep_learning")

  if (tune) {
    model_spec <- mlp(
      hidden_units = tune(),
      penalty = tune(),
      epochs = tune()
    ) %>%
      set_mode(task) %>%
      set_engine("keras")
  } else {
    model_spec <- mlp(
      hidden_units = defaults$hidden_units,
      penalty = defaults$penalty,
      epochs = defaults$epochs
    ) %>%
      set_mode(task) %>%
      set_engine("keras")
  }
  list(model_spec = model_spec)
}

#' Define Linear Discriminant Analysis Model Specification
#'
#' @inheritParams define_logistic_regression_spec
#' @return List containing the model specification (`model_spec`).
#' @importFrom parsnip set_mode set_engine discrim_linear
define_lda_spec <- function(task) {
  if (task != "classification") {
    stop("LDA is only applicable for classification tasks.")
  }
  model_spec <- discrim_linear() %>%
    set_mode("classification") %>%
    set_engine("MASS")
  list(model_spec = model_spec)
}

#' Define Quadratic Discriminant Analysis Model Specification
#'
#' @inheritParams define_logistic_regression_spec
#' @return List containing the model specification (`model_spec`).
#' @importFrom parsnip set_mode set_engine discrim_quad
define_qda_spec <- function(task) {
  if (task != "classification") {
    stop("QDA is only applicable for classification tasks.")
  }
  model_spec <- discrim_quad() %>%
    set_mode("classification") %>%
    set_engine("MASS")
  list(model_spec = model_spec)
}

#' Define Bagging Model Specification
#'
#' @inheritParams define_decision_tree_spec
#' @return List containing the model specification (`model_spec`).
#' @importFrom parsnip bag_tree set_mode set_engine
define_bagging_spec <- function(task, tune = FALSE) {
  defaults <- get_default_params("bagging")
  if (tune) {
    model_spec <- bag_tree(
      min_n = tune()
    ) %>%
      set_mode(task) %>%
      set_engine("rpart", times = 25)
  } else {
    model_spec <- bag_tree(
      min_n = defaults$min_n
    ) %>%
      set_mode(task) %>%
      set_engine("rpart", times = 25)
  }
  list(model_spec = model_spec)
}


#' Define Elastic Net Model Specification
#'
#' @param task Character string specifying the task type ("regression").
#' @inheritParams define_random_forest_spec
#' @return List containing the model specification (`model_spec`).
#' @importFrom parsnip linear_reg set_mode set_engine
define_elastic_net_spec <- function(task, tune = FALSE) {
  if (task != "regression") {
    stop("Elastic Net is only applicable for regression tasks.")
  }
  defaults <- get_default_params("elastic_net")
  if (tune) {
    model_spec <- linear_reg(
      penalty = tune(),
      mixture = tune()
    ) %>%
      set_mode("regression") %>%
      set_engine("glmnet")
  } else {
    model_spec <- linear_reg(
      penalty = defaults$penalty,
      mixture = defaults$mixture
    ) %>%
      set_mode("regression") %>%
      set_engine("glmnet")
  }
  list(model_spec = model_spec)
}


#' Define Bayesian GLM Model Specification
#'
#' @inheritParams define_elastic_net_spec
#' @return List containing the model specification (`model_spec`).
#' @importFrom parsnip linear_reg set_mode set_engine
define_bayes_glm_spec <- function(task) {
  if (!requireNamespace("rstanarm", quietly = TRUE)) {
    stop("The 'rstanarm' package is required but is not installed.")
  }
  if (task != "regression") {
    stop("Bayesian GLM is only applicable for regression tasks.")
  }
  model_spec <- linear_reg() %>%
    set_mode("regression") %>%
    set_engine("stan")
  list(model_spec = model_spec)
}

#' Define Partial Least Squares Model Specification
#'
#' @inheritParams define_elastic_net_spec
#' @return List containing the model specification (`model_spec`).
#' @importFrom parsnip pls set_mode set_engine
define_pls_spec <- function(task, tune = FALSE) {
  if (task != "regression") {
    stop("PLS is only applicable for regression tasks.")
  }
  defaults <- get_default_params("pls")

  if (tune) {
    model_spec <- pls(
      num_comp = tune()
    ) %>%
      set_mode("regression") %>%
      set_engine("mixOmics")
  } else {
    model_spec <- pls(
      num_comp = defaults$num_comp
    ) %>%
      set_mode("regression") %>%
      set_engine("mixOmics")
  }
  list(model_spec = model_spec)
}


#' Define Linear Regression Model Specification
#'
#' @inheritParams define_elastic_net_spec
#' @return List containing the model specification (`model_spec`).
#' @importFrom parsnip linear_reg set_mode set_engine
define_linear_regression_spec <- function(task) {
  if (task != "regression") {
    stop("Linear regression is only applicable for regression tasks.")
  }
  model_spec <- linear_reg() %>%
    set_mode("regression") %>%
    set_engine("lm")
  list(model_spec = model_spec)
}


#' Define Ridge Regression Model Specification
#'
#' @inheritParams define_elastic_net_spec
#' @return List containing the model specification (`model_spec`).
#' @importFrom parsnip linear_reg set_mode set_engine
define_ridge_regression_spec <- function(task, tune = FALSE) {
  if (task != "regression") {
    stop("Ridge regression is only applicable for regression tasks.")
  }
  defaults <- get_default_params("ridge_regression")

  if (tune) {
    model_spec <- linear_reg(
      penalty = tune(),
      mixture = defaults$mixture  # Fixed mixture for Ridge
    ) %>%
      set_mode("regression") %>%
      set_engine("glmnet")
  } else {
    model_spec <- linear_reg(
      penalty = defaults$penalty,
      mixture = defaults$mixture
    ) %>%
      set_mode("regression") %>%
      set_engine("glmnet")
  }
  list(model_spec = model_spec)
}

#' Define Lasso Regression Model Specification
#'
#' @inheritParams define_elastic_net_spec
#' @return List containing the model specification (`model_spec`).
#' @importFrom parsnip linear_reg set_mode set_engine
define_lasso_regression_spec <- function(task, tune = FALSE) {
  if (task != "regression") {
    stop("Lasso regression is only applicable for regression tasks.")
  }
  defaults <- get_default_params("lasso_regression")

  if (tune) {
    model_spec <- linear_reg(
      penalty = tune(),
      mixture = defaults$mixture  # Fixed mixture for Lasso
    ) %>%
      set_mode("regression") %>%
      set_engine("glmnet")
  } else {
    model_spec <- linear_reg(
      penalty = defaults$penalty,
      mixture = defaults$mixture
    ) %>%
      set_mode("regression") %>%
      set_engine("glmnet")
  }
  list(model_spec = model_spec)
}

