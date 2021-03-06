build_rel_susceptibility <- function(rel_susceptibility) {
  n_groups <- carehomes_n_groups()
  if (is.matrix(rel_susceptibility)) {
    if (nrow(rel_susceptibility) != n_groups) {
      stop("'rel_susceptibility' should have as many rows as age groups")
    }
    for (i in seq_len(nrow(rel_susceptibility))) {
      check_rel_susceptibility(rel_susceptibility[i, ])
    }
    mat_rel_susceptibility <- rel_susceptibility
  } else { # create matrix by repeating rel_susceptibility for each age group
    mat_rel_susceptibility <-
      matrix(rep(rel_susceptibility, each = n_groups), nrow = n_groups)
  }
  mat_rel_susceptibility
}


check_rel_susceptibility <- function(rel_susceptibility) {
  if (length(rel_susceptibility) == 0) {
    stop("At least one value required for 'rel_susceptibility'")
  }
  if (any(rel_susceptibility < 0 | rel_susceptibility > 1)) {
    stop("All values of 'rel_susceptibility' must lie in [0, 1]")
  }
  if (rel_susceptibility[[1]] != 1) {
    stop("First value of 'rel_susceptibility' must be 1")
  }
}


build_vaccination_rate <- function(vaccination_rate) {
  n_groups <- carehomes_n_groups()
  if (length(vaccination_rate) > 1) {
    if (length(vaccination_rate) != n_groups) {
      stop("'vaccination_rate' should have as many elements as age groups")
    }
    if (any(vaccination_rate < 0)) {
      stop("'vaccination_rate' must have only non-negative values")
    }
    vect_vaccination_rate <- vaccination_rate
  } else { # create vector by repeating vaccination_rate for each age group
    vect_vaccination_rate <- rep(vaccination_rate, each = n_groups)
  }
  vect_vaccination_rate
}

build_vaccine_progression_rate <- function(vaccine_progression_rate,
                                           n_vacc_classes) {
  n_groups <- carehomes_n_groups()
  if (n_vacc_classes < 3) {
    stop("'n_vacc_classes' should be at least 3")
  }
  # if NULL, set vaccine_progression_rate to 0
  if (is.null(vaccine_progression_rate)) {
    mat_vaccine_progression_rate <- matrix(0, n_groups, n_vacc_classes - 2)
  } else {
    if (is.matrix(vaccine_progression_rate)) {
      if (nrow(vaccine_progression_rate) != n_groups) {
        stop(
          "'vaccine_progression_rate' must have as many rows as age groups")
      }
      if (ncol(vaccine_progression_rate) != n_vacc_classes - 2) {
        stop(
          "'vaccine_progression_rate' must have 'n_vacc_classes - 2' columns")
      }
      if (any(vaccine_progression_rate < 0)) {
        stop("'vaccine_progression_rate' must have only non-negative values")
      }
      mat_vaccine_progression_rate <- vaccine_progression_rate
    } else { # vaccine_progression_rate vector of length n_vacc_classes - 2
      if (!is.vector(vaccine_progression_rate) ||
          length(vaccine_progression_rate) != n_vacc_classes - 2) {
        m1 <- "'vaccine_progression_rate' must be either:"
        m2 <- "a vector of length 'n_vacc_classes - 2' or"
        m3 <- "a matrix with 'n_groups' rows and 'n_vacc_classes - 2' columns"
        stop(paste(m1, m2, m3))
      }
      if (any(vaccine_progression_rate < 0)) {
        stop("'vaccine_progression_rate' must have only non-negative values")
      }
      # create matrix by repeating vaccine_progression_rate for each age group
      mat_vaccine_progression_rate <-
        matrix(rep(vaccine_progression_rate, each = n_groups), nrow = n_groups)
    }
  }
  mat_vaccine_progression_rate
}
