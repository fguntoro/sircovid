context("carehomes")

test_that("can run the carehomes model", {
  p <- carehomes_parameters(sircovid_date("2020-02-07"), "england")
  mod <- carehomes$new(p, 0, 5, seed = 1L)
  end <- sircovid_date("2020-07-31") / p$dt

  initial <- carehomes_initial(mod$info(), 10, p)
  mod$set_state(initial$state, initial$step)

  mod$set_index(carehomes_index(mod$info())$run)
  res <- mod$run(end)

  expected <- rbind(
    icu = c(5, 4, 15, 2, 8),
    general = c(15, 22, 91, 13, 24),
    deaths_comm = c(15947, 15856, 15665, 15767, 15689),
    deaths_hosp = c(310228, 310879, 310092, 310066, 310397),
    admitted = c(150958, 150852, 150885, 149862, 150864),
    new = c(484498, 483435, 484765, 484837, 483353),
    sero_pos = c(2748453, 2799210, 4004426, 2528384, 2727039),
    sympt_cases = c(30884437, 30871629, 30872074, 30872874, 30874007),
    sympt_cases_over25 = c(20922953, 20914231, 20914839, 20915641, 20915614),
    react_pos = c(379, 398, 1640, 269, 398))
  expect_equal(res, expected)
})


test_that("can run the particle filter on the model", {
  start_date <- sircovid_date("2020-02-02")
  pars <- carehomes_parameters(start_date, "england")
  data <- sircovid_data(read_csv(sircovid_file("extdata/example.csv")),
                        start_date, pars$dt)
  ## Add additional columns
  data$deaths_hosp <- data$deaths
  data$deaths_comm <- NA
  data$deaths <- NA
  data$general <- NA
  data$hosp <- NA
  data$admitted <- NA
  data$new <- NA
  data$new_admitted <- NA
  data$npos_15_64 <- NA
  data$ntot_15_64 <- NA
  data$pillar2_pos <- NA
  data$pillar2_tot <- NA
  data$pillar2_cases <- NA
  data$pillar2_over25_pos <- NA
  data$pillar2_over25_tot <- NA
  data$pillar2_over25_cases <- NA
  data$react_pos <- NA
  data$react_tot <- NA

  pf <- carehomes_particle_filter(data, 10)
  expect_s3_class(pf, "particle_filter")

  pf$run(pars)
})
