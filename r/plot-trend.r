library(ggplot2)
library(tidyr)
library(dplyr)
library(rstan)
library(data.table)
library(lubridate)
library(gdata)
library(EnvStats)
library(matrixStats)
library(scales)
library(gridExtra)
library(ggpubr)
library(bayesplot)
library(cowplot)

source("utils/geom-stepribbon.r")
#---------------------------------------------------------------------------
make_three_pannel_plot <- function(){

  args <- commandArgs(trailingOnly = TRUE)
  filename2 <- args[1]

  load(paste0("../modelOutput/results/", filename2))
  print(sprintf("loading: %s",paste0("../modelOutput/results/",filename2)))

  codeToName <- unique(data.frame("code" = d$countryterritoryCode, "name" = d$countriesAndTerritories))

  lastObs <- tail(dates[[1]], 1)
  # lastObs <- as.Date("06/01/2020", format="%m/%d/%y")

  cd <- dates[[1]]
  cd <- cd[cd > lastObs]

  ### final Rt via bayesplot
  dimensions <- dim(out$Rt)
  Rt = (as.matrix(out$Rt[,dimensions[2] - length(cd),])) # HERE! cutting off at June 1st  - remove later
  colnames(Rt) <- codeToName$name
  g = mcmc_intervals(Rt,prob = .9) + 
    ggtitle(sprintf("Rt as of %s", format(lastObs, "%a %B %d")), "with 90% posterior credible intervals") +
    xlab("Rt") + ylab("County") + 
    theme(plot.title = element_text(hjust = 0.5), plot.subtitle = element_text(hjust = 0.5)) # center title and subtitle
  ggsave(sprintf("../modelOutput/figures/Rt_All.png"),g,width=6,height=4)


  # interventions table 
  # NOTE: "covariate" == "intervention"; 
  # e.g., if there are 3 different interventions in the model, then there are 3 covariates here in the code
  covariates = read.csv("../modelInput/ILInterventionsV1.csv", stringsAsFactors = FALSE)
  covariates$Country <- sapply(covariates$Country, as.character)
  covariates$Country <-  sub("840", "", covariates$Country) # cutoff US prefix code - note: maybe this should be in the python etl, not here

  ###


  allErr <- list()
  for(i in 1:length(countries)){

    N <- length(dates[[i]])

    # here! careful - country is an integer right here (is it? double check)
    country <- countries[[i]] # this is the numeric code -> "84017031"
    countryName <- as.character(codeToName$name[codeToName$code == country]) # this is the name -> "Cook"

    predicted_cases <- colMeans(prediction[,1:N,i])
    predicted_cases_li <- colQuantiles(prediction[,1:N,i], probs=.025)
    predicted_cases_ui <- colQuantiles(prediction[,1:N,i], probs=.975)
    predicted_cases_li2 <- colQuantiles(prediction[,1:N,i], probs=.25)
    predicted_cases_ui2 <- colQuantiles(prediction[,1:N,i], probs=.75)
        
    estimated_deaths <- colMeans(estimated.deaths[,1:N,i])
    estimated_deaths_li <- colQuantiles(estimated.deaths[,1:N,i], probs=.025)
    estimated_deaths_ui <- colQuantiles(estimated.deaths[,1:N,i], probs=.975)
    estimated_deaths_li2 <- colQuantiles(estimated.deaths[,1:N,i], probs=.25)
    estimated_deaths_ui2 <- colQuantiles(estimated.deaths[,1:N,i], probs=.75)
    
    rt <- colMeans(out$Rt[,1:N,i])
    rt_li <- colQuantiles(out$Rt[,1:N,i],probs=.025)
    rt_ui <- colQuantiles(out$Rt[,1:N,i],probs=.975)
    rt_li2 <- colQuantiles(out$Rt[,1:N,i],probs=.25)
    rt_ui2 <- colQuantiles(out$Rt[,1:N,i],probs=.75)
        
    # NOTE: `country` is an integer - should be okay here
    covariates_country <- covariates[which(covariates$Country == country), 3:ncol(covariates), drop=FALSE]
    
    covariates_country_long <- gather(covariates_country[], key = "key", value = "value")
    covariates_country_long$x <- rep(NULL, length(covariates_country_long$key))
    un_dates <- unique(covariates_country_long$value)
    
    for (k in 1:length(un_dates)){
      idxs <- which(covariates_country_long$value == un_dates[k])
      max_val <- round(max(rt_ui)) + 0.3
      for (j in idxs){
        covariates_country_long$x[j] <- max_val
        max_val <- max_val - 0.3
      }
    }
    
    covariates_country_long$value <- as_date(covariates_country_long$value) 
    covariates_country_long$country <- rep(country, length(covariates_country_long$value))
    
    data_country <- data.frame("time" = as_date(as.character(dates[[i]])), 
                               "country" = rep(country, length(dates[[i]])),
                               "reported_cases" = reported_cases[[i]], 
                               "reported_cases_c" = cumsum(reported_cases[[i]]), 
                               "predicted_cases_c" = cumsum(predicted_cases),
                               "predicted_min_c" = cumsum(predicted_cases_li),
                               "predicted_max_c" = cumsum(predicted_cases_ui),
                               "predicted_cases" = predicted_cases,
                               "predicted_min" = predicted_cases_li,
                               "predicted_max" = predicted_cases_ui,
                               "predicted_min2" = predicted_cases_li2,
                               "predicted_max2" = predicted_cases_ui2,
                               "deaths" = deaths_by_country[[i]],
                               "deaths_c" = cumsum(deaths_by_country[[i]]),
                               "estimated_deaths_c" =  cumsum(estimated_deaths),
                               "death_min_c" = cumsum(estimated_deaths_li),
                               "death_max_c"= cumsum(estimated_deaths_ui),
                               "estimated_deaths" = estimated_deaths,
                               "death_min" = estimated_deaths_li,
                               "death_max"= estimated_deaths_ui,
                               "death_min2" = estimated_deaths_li2,
                               "death_max2"= estimated_deaths_ui2,
                               "rt" = rt,
                               "rt_min" = rt_li,
                               "rt_max" = rt_ui,
                               "rt_min2" = rt_li2,
                               "rt_max2" = rt_ui2)
    
    county_deaths_and_est <- make_plots(data_country = data_country, 
               covariates_country_long = covariates_country_long,
               filename2 = filename2,
               country = countryName,
               code = country)

    allErr[[i]] <- county_deaths_and_est
  }

  cutoff <- max(sapply(allErr, function(x) min(x$time)))
  allErr <- sapply(allErr, function(x) x[x$time >= cutoff & x$time <= lastObs,])

  err_df <- data.frame(time=allErr[,1]$time)

  err_df$deaths <- 0
  err_df$est <- 0
  for (i in 1:dim(allErr)[2]){
    err_df$deaths <- err_df$deaths + allErr[,i]$deaths
    err_df$est <- err_df$est + allErr[,i]$est
  }

  ### % error 

  # may need to guard against dividing by 0 here
  err_df$err <- (err_df$est - err_df$deaths) / err_df$deaths

  error_plot(
    df = err_df,
    target = "err",
    title = "All County Daily Deaths % Error",
    path = "percent_error_all.png"
  )

  ### scaled error

  err_df$err_raw <- err_df$est - err_df$deaths
  avg_naive <- mean(abs(diff(err_df$deaths)))
  err_df$err_scaled <- err_df$err_raw / avg_naive

  error_plot(
    df = err_df,
    target = "err_scaled",
    title = "All County Daily Deaths Scaled Error",
    path = "scaled_error_all.png"
  )

  ### absolute scaled error 

  err_df$err_abs_scaled <- abs(err_df$err_raw) / avg_naive

  error_plot(
    df = err_df,
    target = "err_abs_scaled",
    title = "All County Daily Deaths Absolute Scaled Error",
    path = "abs_scaled_error_all.png"
  )

}

error_plot <- function(df, target, title, path){
    p <- ggplot(df) +
      ggtitle(title) + 
      geom_bar(data = df, aes(x = time, y = !!sym(target)), 
              fill = "coral4", stat='identity', alpha=0.5) + 
      xlab("Time") +
      ylab("Error") +
      labs(subtitle=sprintf("avg_err: %f", mean(df[[target]]))) +
      scale_x_date(date_breaks = "weeks", labels = date_format("%e %b")) + 
      theme_pubr() + 
      theme(axis.text.x = element_text(angle = 45, hjust = 1), 
          plot.title = element_text(hjust = 0.5),
          legend.position = "None") + 
      guides(fill=guide_legend(ncol=1))

    save_plot(filename = file.path("../modelOutput/figures", path), p)

}

#---------------------------------------------------------------------------

# todo: break down into 3 fn's - modular, man, modular

make_plots <- function(data_country, covariates_country_long, 
                       filename2, country, code){

    countyDir <- file.path("../modelOutput/figures", code)
    dir.create(countyDir, showWarnings = FALSE)

    ## p0 - scaled error plot
    deaths_err <- data.frame(time=data_country$time, deaths=data_country$deaths, est=data_country$estimated_deaths, deaths_c=data_country$deaths_c)

    # index = which(d1$cases>0)[1]
    index <- which(deaths_err$deaths_c>10)[1]
    deaths_err <- deaths_err[index:nrow(deaths_err),]

    # MASE : https://en.wikipedia.org/wiki/Mean_absolute_scaled_error
    # https://robjhyndman.com/papers/foresight.pdf
    # file:///Users/mattgarvin/Downloads/A-note-on-the-MASE-Revision-for-IJF.pdf

    deaths_err$err_raw <- deaths_err$est - deaths_err$deaths
    avg_naive <- mean(abs(diff(deaths_err$deaths)))
    deaths_err$err_scaled <- deaths_err$err_raw / avg_naive
    mase <- mean(deaths_err$err_scaled)

    error_plot(
      df = deaths_err,
      target = "err_scaled",
      title = paste0(country, " County Daily Deaths Scaled Error"),
      path = file.path(code, "scaled_error.png")
    )

    ## p1

    data_cases_95 <- data.frame(data_country$time, data_country$predicted_min, 
                                data_country$predicted_max)
    names(data_cases_95) <- c("time", "cases_min", "cases_max")
    data_cases_95$key <- rep("nintyfive", length(data_cases_95$time))
    data_cases_50 <- data.frame(data_country$time, data_country$predicted_min2, 
                                data_country$predicted_max2)
    names(data_cases_50) <- c("time", "cases_min", "cases_max")
    data_cases_50$key <- rep("fifty", length(data_cases_50$time))
    data_cases <- rbind(data_cases_95, data_cases_50)
    levels(data_cases$key) <- c("ninetyfive", "fifty")
    
    p1 <- ggplot(data_country) +
        ggtitle(paste0(country, " County Daily Cases")) + 
        geom_bar(data = data_country, aes(x = time, y = reported_cases), 
                fill = "coral4", stat='identity', alpha=0.5) + 
        geom_ribbon(data = data_cases, 
                    aes(x = time, ymin = cases_min, ymax = cases_max, fill = key)) +
        xlab("Time") +
        ylab("Cases") +
        scale_x_date(date_breaks = "weeks", labels = date_format("%e %b")) + 
        scale_fill_manual(name = "", labels = c("50%", "95%"),
                        values = c(alpha("deepskyblue4", 0.55), 
                                    alpha("deepskyblue4", 0.45))) + 
        theme_pubr() + 
        theme(axis.text.x = element_text(angle = 45, hjust = 1), 
            plot.title = element_text(hjust = 0.5),
            legend.position = "None") + 
        guides(fill=guide_legend(ncol=1))

    save_plot(filename = file.path(countyDir, "cases.png"), p1)

    ### p2

    data_deaths_95 <- data.frame(data_country$time, data_country$death_min, 
                                data_country$death_max)
    names(data_deaths_95) <- c("time", "death_min", "death_max")
    data_deaths_95$key <- rep("nintyfive", length(data_deaths_95$time))
    data_deaths_50 <- data.frame(data_country$time, data_country$death_min2, 
                                data_country$death_max2)
    names(data_deaths_50) <- c("time", "death_min", "death_max")
    data_deaths_50$key <- rep("fifty", length(data_deaths_50$time))
    data_deaths <- rbind(data_deaths_95, data_deaths_50)
    levels(data_deaths$key) <- c("ninetyfive", "fifty")
    
    p2 <-   ggplot(data_country, aes(x = time)) +
        ggtitle(paste0(country, " County Daily Deaths")) +
        geom_bar(data = data_country, aes(y = deaths, fill = "reported"),
                fill = "coral4", stat='identity', alpha=0.5) +
        geom_ribbon(
        data = data_deaths,
        aes(ymin = death_min, ymax = death_max, fill = key)) +
        xlab("Time") +
        ylab("Deaths") +
        scale_x_date(date_breaks = "weeks", labels = date_format("%e %b")) +
        scale_fill_manual(name = "", labels = c("50%", "95%"),
                        values = c(alpha("deepskyblue4", 0.55), 
                                    alpha("deepskyblue4", 0.45))) + 
        theme_pubr() + 
        theme(axis.text.x = element_text(angle = 45, hjust = 1), 
            plot.title = element_text(hjust = 0.5),
            legend.position = "None") + 
        guides(fill=guide_legend(ncol=1))

    save_plot(filename = file.path(countyDir, "deaths.png"), p2)
    
    ### p3

    plot_labels <- c("lockdown")
    
    # Plotting interventions
    data_rt_95 <- data.frame(data_country$time, 
                            data_country$rt_min, data_country$rt_max)
    names(data_rt_95) <- c("time", "rt_min", "rt_max")
    data_rt_95$key <- rep("nintyfive", length(data_rt_95$time))
    data_rt_50 <- data.frame(data_country$time, data_country$rt_min2, 
                            data_country$rt_max2)
    names(data_rt_50) <- c("time", "rt_min", "rt_max")
    data_rt_50$key <- rep("fifty", length(data_rt_50$time))
    data_rt <- rbind(data_rt_95, data_rt_50)
    levels(data_rt$key) <- c("ninetyfive", "fifth")
    
    p3 <- ggplot(data_country) +
        ggtitle(paste0(country, " County Estimated Rt")) +
        geom_stepribbon(data = data_rt, aes(x = time, 
                                            ymin = rt_min, ymax = rt_max, 
                                            group = key,
                                            fill = key)) +
        geom_hline(yintercept = 1, color = 'black', size = 0.1) + 
        # missing values in one row -> warning -> td: double check this
        geom_segment(data = covariates_country_long,
                    aes(x = value, y = 0, xend = value, yend = max(x)), 
                    linetype = "dashed", colour = "grey", alpha = 0.75) +
        # missing values in one row -> warning
        geom_point(data = covariates_country_long, aes(x = value, 
                                                    y = x, 
                                                    group = key, 
                                                    shape = key, 
                                                    col = key), size = 2) +
        xlab("Time") + 
        ylab(expression(R[t])) +
        scale_fill_manual(name = "", labels = c("50%", "95%"),
                        values = c(alpha("seagreen", 0.75), alpha("seagreen", 0.5))) + 
        scale_shape_manual(name = "Interventions", labels = plot_labels,
                        values = c(21, 22, 23, 24, 25, 12)) + 
        scale_colour_discrete(name = "Interventions", labels = plot_labels) + 
        scale_x_date(date_breaks = "weeks", labels = date_format("%e %b")) + 
        theme_pubr() + 
        theme(axis.text.x = element_text(angle = 45, hjust = 1),
                    plot.title = element_text(hjust = 0.5),
                    legend.position="right")

    save_plot(filename = file.path(countyDir, "Rt.png"), p3)

    df_err <- data.frame(time=deaths_err$time, deaths=deaths_err$deaths, est=deaths_err$est)
    return(df_err)
}

make_three_pannel_plot()
