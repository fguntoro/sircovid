## General things that we need but that aren't that interesting.

## We always use these age bands, so rather than detect them, we will
## check that things conform to them.
sircovid_age_bins <- function() {
  end <- c(seq(4, 79, by = 5), 100)
  start <- c(0, end[-length(end)] + 1L)
  list(start = start, end = end)
}


check_age_bins <- function(age_headers) {
  bins <- sircovid_age_bins()
  expected <- sprintf("%d to %d", bins$start, bins$end)
  if (!identical(age_headers, expected)) {
    stop(sprintf("Incorrect age bands:\nexpected: %s\ngiven: %s",
                 paste(squote(expected), collapse = ", "),
                 paste(squote(age_headers), collapse = ", ")))
  }
  bins
}


sircovid_population <- function(region) {
  if (is.null(region)) {
    stop("'region' must not be NULL")
  }

  if (is.null(cache$population)) {
    cache$population <- read_csv(sircovid_file("extdata/population.csv"))
  }

  population <- cache$population[[tolower(region)]]
  if (is.null(population)) {
    valid <- setdiff(names(cache$population), "age")
    stop(sprintf("Population not found for '%s': must be one of %s",
                 region, paste(squote(valid), collapse = ", ")))
  }

  population
}


##' @importFrom stats dnbinom rexp
ll_nbinom <- function(data, model, k, exp_noise) {
  if (is.na(data)) {
    return(numeric(length(model)))
  }
  mu <- model + rexp(length(model), rate = exp_noise)
  dnbinom(data, k, mu = mu, log = TRUE)
}


##' @importFrom stats dbinom
ll_binom <- function(data_x, data_size, model_prob) {
  if (is.na(data_x) || is.na(data_size)) {
    return(numeric(length(model_prob)))
  }
  dbinom(data_x, data_size, model_prob, log = TRUE)
}


ll_betabinom <- function(data_x, data_size, model_prob, rho) {
  if (is.na(data_x) || is.na(data_size)) {
    return(numeric(length(model_prob)))
  }
  dbetabinom(data_x, data_size, model_prob, rho, log = TRUE)
}


dbetabinom <- function(x, size, prob, rho, log = FALSE) {

  a <- prob * (1 / rho - 1)
  b <- (1 - prob) * (1 / rho - 1)

  out <- lchoose(size, x) + lbeta(x + a, size - x + b) - lbeta(a, b)

  if (!log) {
    out <- exp(out)
  }

  out
}


##' @importFrom stats rexp
test_prob_pos <- function(pos, neg, sensitivity, specificity, exp_noise) {

  ## We add some exponential noise to the number of positives and negatives
  ## to help ensure prob_pos is not 0 or 1. If e.g. prob_pos were 0 and there
  ## were individuals who tested positive, this would result in a weight of 0
  ## for a particle. If all particles have weights of 0, the particle filter
  ## breaks. The exponential noise produces small non-zero weights in these
  ## circumstances to prevent the particle filter from breaking.

  pos <- pos + rexp(length(pos), exp_noise)
  neg <- neg + rexp(length(neg), exp_noise)

  prob_pos <- (sensitivity * pos + (1 - specificity) * neg) / (pos + neg)
  prob_pos
}


sircovid_transmission_matrix <- function(region) {
  if (is.null(cache$transmission_matrix[[region]])) {
    if (is.null(cache$transmission_matrix)) {
      cache$transmission_matrix <- list()
    }
    age_bins <- sircovid_age_bins()

    max_polymod_age <- 70

    ## Survey population in socialmixr format
    survey_pop <- data_frame(
      "lower.age.limit" = sircovid_age_bins()$start,
      population = sircovid_population(region))

    ## Get the contact matrix from socialmixr; polymod only
    ## goes up to age 70
    contact <- suppressMessages(socialmixr::contact_matrix(
      survey.pop = survey_pop,
      socialmixr::polymod,
      countries = "United Kingdom",
      age.limits = age_bins$start[age_bins$start <= max_polymod_age],
      symmetric = TRUE))

    ## Transform the matrix to the (symetrical) transmission matrix
    ## rather than the contact matrix
    transmission <- contact$matrix /
      rep(contact$demography$population, each = ncol(contact$matrix))

    ## POLYMOD has a max age of 70, so older bins need to be filled in
    ## assumes that the probability of contact remains as in POLYMOD
    ## and that contacts are the same in 70+ and 80+
    extra <- age_bins$start[age_bins$start > max_polymod_age]
    i <- c(seq_len(nrow(transmission)), rep(nrow(transmission), length(extra)))
    transmission <- transmission[i, i]

    ## Rename for cosmetic reasons only
    nms <- sprintf("[%d,%d)", age_bins$start, age_bins$end)
    dimnames(transmission) <- list(nms, nms)

    cache$transmission_matrix[[region]] <- transmission
  }

  cache$transmission_matrix[[region]]
}


severity_default <- function() {
  if (is.null(cache$severity_default)) {
    cache$severity_default <-
      read_csv(sircovid_file("extdata/severity_default.csv"))
  }
  cache$severity_default
}


add_trajectory_incidence <- function(trajectories, states, suffix = "_inc") {
  assert_is(trajectories, "mcstate_trajectories")

  ## In order to compute incidence we have to add two NA values; one
  ## is the usual one dropped in a rolling difference, the other is
  ## dropped as the first time interval is potentially much longer
  ## than a day.
  incidence <- function(x) {
    c(NA, NA, diff(x[-1L]))
  }

  ## This is less complicated than it looks, but takes a diff over the
  ## time dimension and converts back into the correct array dimension
  ## order.
  traj_inc <- aperm(
    apply(trajectories$state[states, , , drop = FALSE], c(1, 2), incidence),
    c(2, 3, 1))
  rownames(traj_inc) <- paste0(states, suffix)
  trajectories$state <- abind1(trajectories$state, traj_inc)

  trajectories
}

##' Combine trajectories across multiple runs
##'
##' @title Combine trajectories
##'
##' @param samples A list of samples from [carehomes_forecast()]
##'
##' @param rank Logical, indicating if trajectories should be ranked
##'   before combination.
##'
##' @return A set of combined trajectories (not a combined samples object).
##'
##' @export
combine_trajectories <- function(samples, rank = TRUE) {
  states <- lapply(samples, function(x) x$trajectories$state)

  ## Ensure all trajectories are the same length
  dates <- lapply(samples, function(x) x$trajectories$date)
  dates_keep <- dates[[1]]
  for (i in seq_along(dates)[-1]) {
    dates_keep <- intersect(dates_keep, dates[[i]])
  }

  ## This really only needs doing if length(unique(dates)) > 1 but is
  ## relatively harmless otherwise.
  states <- lapply(seq_along(dates), function(i)
    states[[i]][, , dates[[i]] %in% dates_keep, drop = FALSE])

  if (rank) {
    states <- lapply(states, rank_trajectories)
  }

  ## This is a sum over regions, somewhat equivalent to a do.call over
  ## this list
  state <- Reduce(`+`, states)

  ## We count a date as "predicted" if any of the entries have a
  ## prediction on that day.
  predicted <- vapply(seq_along(dates), function(i)
    samples[[i]]$trajectories$predicted[dates[[i]] %in% dates_keep],
    logical(length(dates_keep)))
  predicted <- apply(predicted, 1, any)

  ## Create a mcstate_trajectories object based on the first element,
  ## filtered by the the dates. The state is updated but everything
  ## else is valid.
  trajectories <- samples[[1]]$trajectories
  trajectories$predicted <- predicted
  trajectories$date <- trajectories$date[dates[[1]] %in% dates_keep]
  trajectories$state <- state

  trajectories
}


rank_trajectories <- function(state) {
  ## Reorder the trajectories by the area under each curve
  for (i in seq_len(nrow(state))) {
    rank_state <- order(rowSums(state[i, , ], na.rm = TRUE))
    state[i, , ] <- state[i, rank_state, ]
  }

  state
}


##' Combine Rt across multiple runs.
##'
##' @title Combine Rt estimates
##'
##' @param rt A list of Rt calculations from
##'   [carehomes_Rt_trajectories()] (though any Rt calculation that
##'   confirms to this will work)
##'
##' @param samples A list of samples from [carehomes_forecast()]
##'
##' @return A list of Rt output in the same structure as the first
##'   element of `rt`. All Rt estimates will be aggregated across
##'   regions (or whatever else you are aggregating on) based on the
##'   parameters in `samples`.
##'
##' @export
combine_rt <- function(rt, samples) {
  ## Ensure all trajectories are the same length
  ret <- rt[[1L]]
  what <- setdiff(names(ret), c("date", "step"))
  ret[what] <- lapply(what, combine_rt1, rt, samples)
  ret
}


combine_rt1 <- function(what, rt, samples) {
  dates <- lapply(samples, function(x) x$trajectories$date)
  dates_keep <- dates[[1]]
  for (i in seq_along(dates)[-1]) {
    dates_keep <- intersect(dates_keep, dates[[i]])
  }
  idx <- lapply(seq_along(samples), function(i) dates[[i]] %in% dates_keep)

  incidence <- Map(function(s, i)
    t(s$trajectories$state["infections_inc", , i]), samples, idx)

  rt_what <- Map(function(r, i) r[[what]][i, ], rt, idx)

  ## Calculate rank of particles by area under Rt curve
  rank_x <- lapply(rt_what, function(x) order(colSums(x)))

  ## Rank based on the transpose (vs when this is done in the trajectories).
  reorder_by_rank <- function(x, rank_x) {
    Map(function(x, rank) x[, rank], x, rank_x)
  }

  ## Rank Rt and incidence
  x <- reorder_by_rank(rt_what, rank_x)
  w <- reorder_by_rank(incidence, rank_x)
  sum_w <- Reduce(`+`, w)

  ## Weight Rt by incidence to combine regions
  ret <- Map(function(x, w) x * w / sum_w, x, w)

  Reduce(`+`, ret)
}
