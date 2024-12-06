% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/train_models.R
\name{define_deep_learning_spec}
\alias{define_deep_learning_spec}
\title{Define Deep Learning Model Specification (keras)}
\usage{
define_deep_learning_spec(task, tune = FALSE)
}
\arguments{
\item{task}{Character string specifying the task type: "classification" or "regression".}

\item{tune}{Logical indicating whether to use tuning parameters.}
}
\value{
List containing the model specification (`model_spec`).
}
\description{
Define Deep Learning Model Specification (keras)
}
