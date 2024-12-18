% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/evaluate_models.R
\name{evaluate_models}
\alias{evaluate_models}
\title{Evaluate Models Function}
\usage{
evaluate_models(models, train_data, test_data, label, task, metric = NULL)
}
\arguments{
\item{models}{A list of trained model objects.}

\item{train_data}{Preprocessed training data frame.}

\item{test_data}{Preprocessed test data frame.}

\item{label}{Name of the target variable.}

\item{task}{Type of task: "classification" or "regression".}

\item{metric}{The performance metric to optimize (e.g., "accuracy", "rmse").}
}
\value{
A list with two elements:
  \describe{
    \item{performance}{A named list of performance metric tibbles for each model.}
    \item{predictions}{A named list of data frames with columns including truth, predictions, and probabilities per model.}
  }
}
\description{
Evaluates the trained models on the test data and computes performance metrics.
}
