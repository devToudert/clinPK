#' Cmax for linear 1-compartment PK model at steady state
#'
#' Takes single values for dose or model parameters, or vector of either dose or parameters (but not both).
#'
#' @param dose dose
#' @param tau dosing interval
#' @param CL clearance
#' @param V volume of distrubition
#' @param t_inf infusion time
#' @param ruv residual variability, specified as list with optional arguments for proportional, additive, or exponential components, e.g. `list(prop=0.1, add=1, exp=0)`
#' @examples
#' pk_1cmt_inf_cmax_ss(dose = 500, tau = 12, t_inf = 2, CL = 5, V = 50)
#' @export
pk_1cmt_inf_cmax_ss <- function (dose, tau, CL, V, t_inf, ruv = NULL) {
  tmp <- (dose / (CL * t_inf)) * ( (1-exp(-(CL/V)*t_inf)) / (1-exp(-(CL/V)*tau)) )
  if(!is.null(ruv)) {
    tmp <- add_ruv (tmp, ruv)
  }
  tmp
}
