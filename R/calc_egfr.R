#' Calculate eGFR
#'
#' Calculate the estimated glomerulal filtration rate (an estimate of renal function) based on measured serum creatinine using one of the following approaches:
#' - Cockcroft-Gault (using weight, ideal body weight, or adjusted body weight)
#' - Revised Lund-Malmo
#' - Modification of Diet in Renal Disease study (MDRD)
#' - Schwartz
#' - Schwartz revised / bedside
#' - Jelliffe
#' - Jelliffe (for unstable renal function)
#' - Wright
#'
#' Equations for estimation of eGFR from Cystatin C concentrations are available from the `calc_egfr_cystatin()` function.
#'
#' @param method eGFR estimation method, choose from `cockcroft_gault`, `cockcroft_gault_ideal`, `cockcroft_gault_adjusted`, `cockcroft_gault_adaptive `mdrd`, `ckd_epi`, malmo_lund_revised`, `schwartz`, `jelliffe`, `jellife_unstable`, `wright`
#' @param sex sex
#' @param age age
#' @param scr serum creatinine (mg/dL)
#' @param scr_unit, `mg/dL` or `micromol/L` (==`umol/L`)
#' @param race `black` or `other`
#' @param weight weight
#' @param height height, only relevant when converting to/from BSA-relative unit
#' @param bsa body surface area
#' @param bsa_method BSA estimation method, see `bsa()` for details
#' @param times vector of sampling times (in days!) for creatinine (only used in Jelliffe equation for unstable patients)
#' @param ckd chronic kidney disease? (Schwartz equations only)
#' @param relative `TRUE`/`FALSE`. Report eGFR as per 1.73 m2? Requires BSA if re-calculation required. If `NULL` (=default), will choose value typical for `method`.
#' @param unit_out `ml/min` (default), `L/hr`, or `mL/hr`
#' @param preterm is patient preterm?
#' @param min_value minimum value (`NULL` by default)
#' @param max_value maximum value (`NULL` by default)
#' @param verbose verbocity, show guidance and warnings. `TRUE` by default
#' @param ... arguments passed on
#' @examples
#' calc_egfr(sex = "male", age = 50, scr = 1.1, weight = 70)
#' calc_egfr(sex = "male", age = 50, scr = 1.1, weight = 70, unit_out = "L/hr")
#' calc_egfr(sex = "male", age = 50, scr = 1.1, weight = 70, bsa = 1.8, method = "ckd_epi")
#' calc_egfr(sex = "male", age = 50, scr = c(1.1, 0.8),
#'   weight = 70, height = 170, method = "jelliffe")
#' calc_egfr(sex = "male", age = 50, scr = c(1.1, 0.8),
#'   weight = 70, height = 170, method = "jelliffe_unstable")
#' calc_egfr(sex = "male", age = 50, scr = 1.1,
#'   weight = 70, bsa = 1.6, method = "malmo_lund_rev", relative = FALSE)
#' @export
calc_egfr <- function (
  method = "cockcroft_gault",
  sex = NULL,
  age = NULL,
  scr = NULL,
  scr_unit = NULL,
  race = "other",
  weight = NULL,
  height = NULL,
  bsa = NULL,
  preterm = FALSE,
  ckd = FALSE,
  times = NULL,
  bsa_method = "dubois",
  relative = NULL,
  unit_out = "mL/min",
  verbose = TRUE,
  min_value = NULL,
  max_value = NULL,
  ...
  ) {
    method <- gsub("-", "_", tolower(method))
    method <- gsub("cockroft", "cockcroft", tolower(method)) # legacy support for typo
    available_methods <- c(
      "cockcroft_gault", "cockcroft_gault_ideal", "cockcroft_gault_adjusted",
      "cockcroft_gault_adaptive",
      "malmo_lund_revised", "malmo_lund_rev", "lund_malmo_revised", "lund_malmo_rev",
      "mdrd", "ckd_epi", "schwartz", "schwartz_revised", "bedside_schwartz", "jelliffe", "jelliffe_unstable",
      "wright")
    if(!method %in% available_methods) {
      stop(paste0("Sorry, eGFR calculation method not recognized! Please choose from: ", paste0(available_methods, collapse=" ")))
    }
    if(!is.null(scr_unit)) {
      scr_units_allowed <- c("mg/dl", "micromol/l", "mumol/l", "umol/l")
      if(!all(tolower(scr_unit) %in% scr_units_allowed)) {
        stop("Sorry, specified serum Cr unit not recognized!")
      }
    }
    weight_for_egfr <- "Total BW"
    if(method %in% c("cockcroft_gault_ideal")) {
      if(is.nil(height) || is.nil(sex) || is.nil(weight) || is.nil(age)) {
        stop("Cockcroft-Gault using adjusted body weight requires: scr, sex, weight, height, and age as input!")
      }
    }
    if(method %in% c("cockcroft_gault_ideal")) {
      weight_for_egfr <- "Ideal BW"
      weight <- calc_ibw(height = height, age = age, sex = sex) # recalculate wt to ibw
    }
    if(method %in% c("cockcroft_gault_adjusted")) {
      if(is.nil(height) || is.nil(sex) || is.nil(weight) || is.nil(age)) {
        stop("Cockcroft-Gault using ideal or adjusted body weight requires: scr, sex, weight, height, and age as input!")
      }
      ibw <- calc_ibw(weight = weight, height = height, age = age, sex = sex)
      weight <- calc_abw(weight = weight, ibw = ibw, ...) # recalculate wt to abw, potentially specify factor
      weight_for_egfr <- "Adjusted BW"
    }
    if(method == "cockcroft_gault_adaptive") {
      if(is.nil(height) || is.nil(sex) || is.nil(weight) || is.nil(age)) {
        stop("Cockcroft-Gault using adaptive body weight requires: scr, sex, weight, height, and age as input!")
      }
      tmp <- calc_dosing_weight(weight = weight, height = height, age = age, sex = sex, verbose = verbose, ...)
      weight <- tmp$value
      weight_for_egfr <- tmp$type
    }
    if(is.null(scr_unit)) {
      if(verbose) message("Creatinine unit not specified, assuming mg/dL.")
      scr_unit <- "mg/dl"
    }
    if(!is.nil(sex)) {
      sex <- tolower(sex)
    }
    if(is.nil(scr)) {
      stop("Serum creatinine value required!")
    }
    if(is.nil(relative)) {
      relative <- TRUE # most equations report in /1.73m2
      if(method == "cockcroft_gault") { # except CG
        relative <- FALSE
      }
    }
    if(!is.nil(weight) && !is.nil(height)) {
      if(is.nil(bsa)) {
        bsa <- calc_bsa(weight, height, "dubois")$value
      }
    }
    unit_out <- tolower(unit_out)
    scr_unit <- gsub("%2F", "/", scr_unit)
    unit_out <- gsub("%2F", "/", unit_out)
    if(length(scr_unit) == 1 && length(scr) > 1) {
      scr_unit <- rep(scr_unit, length(scr))
    }
    if(method %in% available_methods) {
      crcl <- c()
      unit <- unit_out
      for (i in 1:length(scr)) {
        if(method == "wright") {
          if(is.nil(scr[i]) || is.nil(sex) || is.nil(age) || is.nil(bsa)) {
            stop("Wright equation requires: scr, sex, bsa (or weight and height), and age as input!")
          }
          if(tolower(scr_unit[i]) == "mg/dl") {
            scr[i] <- scr[i] * 88.40
          }
          crcl[i] = ((6580 - (38.8 * age)) * bsa * (1-(0.168*ifelse(sex == "male", 0, 1))))/scr[i]
          if(!relative) {
            if(is.nil(bsa)) {
              stop("Error: bsa not specified, or weight and height not specified! Can't convert between absolute and relative eGFR!")
            } else {
              crcl[i] <- crcl[i] * (bsa/1.73)
            }
          } else {
            unit <- paste0(unit_out, "/1.73m^2")
          }
        }
        if(method == "jelliffe") {
          if(is.nil(scr[i]) || is.nil(sex) || is.nil(age) || is.nil(bsa)) {
            stop("Jelliffe equation requires: scr, sex, bsa (or weight and height), and age as input!")
          }
          if(tolower(scr_unit[i]) == "mg/dl") {
            scr[i] <- scr[i] * 88.40
          }
          crcl[i] = ((98 - 0.8*(age - 20)) * (1 - 0.01 * ifelse(sex == "male", 0, 1)) * bsa/1.73) / (scr[i]*0.0113)
          if(!relative) {
            if(is.nil(bsa)) {
              stop("Error: bsa not specified, or weight and height not specified! Can't convert between absolute and relative eGFR!")
            } else {
              crcl[i] <- crcl[i] * (bsa/1.73)
            }
          } else {
            unit <- paste0(unit_out, "/1.73m^2")
          }
        }
        if(method == "jelliffe_unstable") {
          if(is.nil(scr[i]) || is.nil(sex) || is.nil(age) || is.nil(weight)) {
            stop("Jelliffe equation requires: scr, sex, weight, and age as input!")
          }
          if(tolower(scr_unit[i]) %in% c("umol/l", "mumol/l", "micromol/l")) {
            scr[i] <- scr[i] / 88.40
          }
          vol <- 0.4 * weight * 10
          scr1 <- scr[i]
          scr2 <- scr[i]
          if(i > 1) {
            scr1 <- scr[i-1]
          }
          scr_av <- mean(c(scr1,scr2))
          if(is.null(times)) {
            dt <- 1 # assume 1 day difference
          } else {
            if(i > 1) {
              dt <- times[i] - times[i-1]
              if(dt <= 0) {
                dt <- 1
              }
            } else {
              dt <- 1 # doesn't matter, for first obs we're not looking at a previous sample anyhow
            }
          }
          cr_prod <- (29.305-(0.203 * age)) * weight * (1.037-(0.0338 * scr_av)) * ifelse(sex == "male", 0.85, 0.765)
          crcl[i] <- ((vol * (scr1 - scr2)/dt + cr_prod) * 100) / (1440 * scr_av)
          if(crcl[i] < 1) { # sanity check
            crcl[i] <- 1
            warning("Some eGFR values calculated by Jellife equation for unstable patients were < 1 mL/min. Please check input data.")
          }
          if(!relative) {
            if(is.nil(bsa)) {
              stop("Error: bsa not specified, or weight and height not specified! Can't convert between absolute and relative eGFR!")
            } else {
              crcl[i] <- crcl[i] * (bsa/1.73)
            }
          } else {
            unit <- paste0(unit_out, "/1.73m^2")
          }
        }
        if(method == "mdrd") {
          if(is.nil(scr[i]) || is.nil(sex) || is.nil(race) || is.nil(age)) {
            stop("MDRD equation requires: scr, sex, race, and age as input!")
          }
          if(tolower(scr_unit[i]) %in% c("umol/l", "mumol/l", "micromol/l")) {
            scr[i] <- scr[i] / 88.40
          }
          f_sex <- 1
          f_race <- 1
          if (sex == "female") { f_sex <- 0.762 }
          if (race == "black") { f_race <- 1.210 }
          crcl[i] <- 186 * scr[i]^(-1.154) * f_sex * f_race * age^(-0.203)
          if(!relative) {
            if(is.nil(bsa)) {
              stop("Error: bsa not specified, or weight and height not specified! Can't convert between absolute and relative eGFR!")
            } else {
              crcl[i] <- crcl[i] * (bsa/1.73)
              unit <- unit
            }
          } else {
            unit <- paste0(unit_out, "/1.73m^2")
          }
        }
        if(method == "ckd_epi") {
          if(is.nil(scr[i]) || is.nil(sex) || is.nil(race) || is.nil(age)) {
            stop("MDRD equation requires: scr, sex, race, and age as input!")
          }
          if(tolower(scr_unit[i]) %in% c("umol/l", "mumol/l", "micromol/l")) {
            scr[i] <- scr[i] / 88.40
          }
          f_sex <- 1
          f_race <- 1
          if (sex == "female") { f_sex <- 1.018 }
          if (race == "black") { f_race <- 1.159 }
          crcl[i] <- 141 * min(scr[i], 1)^(-0.329) * max(scr[i], 1)^(-1.209) * 0.993^age * f_sex * f_race
          if(!relative) {
            if(is.nil(bsa)) {
              stop("Error: bsa not specified, or weight and height not specified! Can't convert between absolute and relative eGFR!")
            } else {
              crcl[i] <- crcl[i] * (bsa/1.73)
              unit <- unit
            }
          } else {
            unit <- paste0(unit_out, "/1.73m^2")
          }
        }
        if(method %in% c("cockcroft_gault", "cockcroft_gault_ideal", "cockcroft_gault_adjusted", "cockcroft_gault_adaptive")) {
          if(is.nil(scr[i]) || is.nil(sex) || is.nil(weight) || is.nil(age)) {
            stop("cockcroft-Gault equation requires: scr, sex, weight, and age as input!")
          }
          if(tolower(scr_unit[i]) %in% c("umol/l", "mumol/l", "micromol/l")) {
            scr[i] <- scr[i] / 88.40
          }
          f_sex <- 1
          if (sex == "female") {
            f_sex <- 0.85
          }
          crcl[i] <- f_sex * (140-age) / scr[i] * (weight/72)
          if(relative) {
            if(is.nil(bsa)) {
              stop("Error: bsa not specified, or weight and height not specified! Can't convert between absolute and relative eGFR!")
            } else {
              crcl[i] <- crcl[i] / (bsa/1.73)
              unit <- paste0(unit_out, "/1.73m^2")
            }
          }
        }
        if(method == "malmo_lund_revised" || method == "lund_malmo_revised" || method == "lund_malmo_rev" || method == "malmo_lund_rev") {
          if(is.nil(scr) || is.nil(sex) || is.nil(age)) {
            stop("Revised Lund-Malmo equation requires: scr, sex, and age as input!")
          }
          if(tolower(scr_unit[i]) == "mg/dl") {
            scr[i] <- scr[i] * 88.40
          }
          if(sex == "female") {
            if(scr[i] < 150) {
              x <- 2.50 + 0.0121 * (150-scr[i])
            } else {
              x <- 2.50 - 0.926 * log(scr[i]/150)
            }
          } else { # male
            if(scr[i] < 180) {
              x <- 2.56 + 0.00968 * (180-scr[i])
            } else {
              x <- 2.56 - 0.926 * log(scr[i]/150)
            }
          }
          crcl[i] <- exp(x - 0.0158*age + 0.438*log(age))
          if(!relative) {
            if(is.nil(bsa)) {
              stop("Error: bsa not specified, or weight and height not specified! Can't convert between absolute and relative eGFR!")
            } else {
              crcl[i] <- crcl[i] * (bsa/1.73)
            }
          } else {
            unit <- paste0(unit_out, "/1.73m^2")
          }
        }
        if(method %in% c("schwartz", "schwartz_revised", "bedside_schwartz")) {
          if(method == "schwartz") {
            if(is.nil(scr[i]) || is.nil(age) || is.nil(sex) || is.nil(height) || is.nil(preterm)) {
              stop("Schwartz equation requires: scr, sex, height, preterm, and age as input!")
            }
          }
          if(method %in% c("schwartz_revised", "bedside_schwartz")) {
            if(is.nil(scr[i]) || is.nil(age) || is.nil(sex) || is.nil(height)) {
              stop("Revised/Bedside Schwartz equation requires: scr, sex, height, and age as input!")
            }
          }
          if(tolower(scr_unit[i]) %in% c("umol/l", "mumol/l", "micromol/l")) {
            scr[i] <- scr[i] / 88.40
          }
          if(method %in% c("bedside_schwartz", "schwartz_revised")) {
            k <- 0.413
            if(age < 1) message("This equation is not meant for patients < 1 years of age.")
          } else {
            ## Original Schwartz equation from 1987:
            k <- 0.55
            if (age < 1) {
              k <- 0.45
              if(preterm) {
                k <- 0.33
              }
            } else {
              if(age > 13 && sex == "male") {
                k <- 0.7
              }
            }
          }
          crcl[i] <- (k * height) / scr[i]
          if(!relative) {
            if(is.nil(bsa)) {
              stop("Error: bsa not specified, or weight and height not specified! Can't convert between absolute and relative eGFR!")
            } else {
              crcl[i] <- crcl[i] * (bsa/1.73)
              if(verbose) message("eGFR from Schwartz commonly reported as relative to 1.73m^2 BSA. Consider using 'relative=TRUE' argument.")
            }
          } else {
            unit <- paste0(unit_out, "/1.73m^2")
          }
        }
        if (length(grep("^l/hr", tolower(unit_out))) > 0) {
          crcl[i] <- crcl[i] * 60 / 1000
        }
        if (length(grep("^ml/hr", tolower(unit_out))) > 0) {
          crcl[i] <- crcl[i] * 60
        }
      }
      if(!is.null(min_value))
        crcl[crcl < min_value] <- min_value
      if(!is.null(max_value))
        crcl[crcl > max_value] <- max_value
      return(list(
        value = crcl,
        unit = unit,
        weight = weight_for_egfr
      ))
    } else {
      return(FALSE)
    }
}
