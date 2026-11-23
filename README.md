# Australian Wine Sales · ADS-506 Module 5

## Project Deliverables

- 📊 [**Interactive Shiny Dashboard**](https://sheshma-jaganathan.shinyapps.io/ads506-wine-forecasts/)
  
- 💻  [**Forecasting notebook**](docs/forecast-notebook.qmd)
  
- 📈 [**Data story**](docs/data-story.qmd)
  
## Introduction

This project uses monthly Australian wine sales from 1980 to 1994 to explore sales patterns and compare forecasting models. The R Shiny app lets users explore six wine varieties without writing code.

## Problem statement

Sales can rise and fall at different times of the year depending on the wine variety. A model that fits past sales well may still miss later peaks or dips. Which model gives the most accurate forecasts for each variety when tested on later months?

## Objective

Compare TSLM, ETS, and ARIMA for selected wine varieties. Use earlier months to train the models and later months to check forecast accuracy. Show actual sales alongside forecasts and prediction intervals so users can see where the models performed well and where they missed.

## Exploratory data analysis

The **Sales history** tab helps users explore long-term changes, unusual months, and recurring seasonal peaks.

- **Timeline** shows how sales changed over time.
- **Month of the year** groups sales by calendar month to show recurring patterns.

## Forecasting models

| Model | How it forecasts sales |
| --- | --- |
| TSLM | Fits a straight-line trend and a separate effect for each month of the year. |
| ETS | Uses exponential smoothing and automatically selects how to represent trend and seasonality. |
| ARIMA | Automatically selects a model using patterns in past sales and forecast errors, including seasonal patterns. |

## Model results

The default comparison trains on January 1980 through December 1993 and tests on the 12 months of 1994.

RMSE and MAE are measured in thousand liters. MAPE is a percentage. Lower values are better. Models are ranked by validation RMSE within each wine variety.

| Wine variety | Model | RMSE | MAE | MAPE |
| --- | --- | ---: | ---: | ---: |
| Fortified | **ETS** | 318.90 | 242.65 | 10.24% |
| Fortified | ARIMA | 328.50 | 266.46 | 11.65% |
| Fortified | TSLM | 426.53 | 362.69 | 16.25% |
| Red | **ARIMA** | 257.86 | 202.54 | 8.63% |
| Red | ETS | 297.16 | 255.37 | 10.43% |
| Red | TSLM | 319.28 | 249.00 | 11.79% |

**ETS** had the lowest validation RMSE for fortified wine. **ARIMA** had the lowest RMSE for red wine. Users can change the split in the app to see whether the rankings hold for another period.

## Tools used

- **R, fpp3, and tidyverts** for monthly time series, model fitting, forecasts, and accuracy.
- **readr, dplyr, and tidyr** for reading and preparing the data.
- **Shiny and bslib** for the interactive app and layout.
- **ggplot2** for sales and forecast charts.
- **Quarto** for the analysis notebook and data story.

## Dashboard Features

- Select one or more of six wine varieties.
- Explore sales over time and patterns by calendar month.
- Adjust the date range, last training month, and forecast horizon.
- Compare TSLM, automatic ETS, and automatic ARIMA.
- View ETS component forms and ARIMA orders.
- Compare training and validation RMSE, MAE, and MAPE.
- View actual sales alongside forecasts with 80% and 95% prediction intervals.
- Download forecast charts and accuracy tables.

## Reproduce locally

### 1. Clone the repository

Run these commands in your terminal:

```powershell
git clone https://github.com/SheshmaJ/australian-wine-sales-forecasting.git
cd australian-wine-sales-forecasting
```

Open this folder in VS Code or RStudio. It should contain `app.R`, `data/`, and `docs/`.

### 2. Install packages and launch the app

Run these commands in an **R console**:

```r
install.packages(
  c("shiny", "bslib", "fpp3", "readr", "urca", "scales"),
  repos = "https://cloud.r-project.org"
)

shiny::runApp(".", launch.browser = TRUE)
```

Keep `data/AustralianWines.csv` in its original folder.

For VS Code PowerShell, if `$rscript` already contains the path to `Rscript.exe`, launch the app with:

```powershell
& $rscript -e "shiny::runApp('.', launch.browser = TRUE)"
```

### 3. Run the notebook

Open `docs/forecast-workflow.qmd` to follow the seven analysis steps.

To render it, install Quarto and these R packages:

```r
install.packages(c("knitr", "rmarkdown"))
```

Then run this command in your terminal:

```powershell
quarto render docs/forecast-workflow.qmd
```

## Deploy to shinyapps.io

Sign in to shinyapps.io and open the account **Tokens** page. Copy the account setup command and run it privately in your R console.

From the folder containing `app.R`, run:

```r
install.packages("rsconnect")

rsconnect::deployApp(
  appDir = ".",
  appName = "ads506-wine-forecasts",
  appFiles = c("app.R", "data/AustralianWines.csv"),
  launch.browser = TRUE
)
```

Open the deployed app in a private browser window to check that it loads.

## About the Data and Models

The course dataset contains monthly Australian wine sales from 1980 to 1994, measured in thousand liters. The app organizes the data as a monthly `tsibble`, with one series for each wine variety.

Missing training values are filled using the most recent available value within the same variety. Missing validation values are excluded from accuracy calculations and remain as gaps in the observed sales.

Models are fitted using training data. Validation scores cover the entire selected validation period, even when the chart displays a shorter forecast horizon.

## How to Navigate the Dashboard

1. Select **Fortified** and **Red**.
2. Set **Sales dates** to **January 1980–December 1994**.
3. Set **Last training month** to **December 1993**.
4. Choose **12 months to predict** and select all three models.
5. Set **Past sales on forecast chart** to **24 months**.
6. Open **Forecast** to recreate the chart.
7. Open **Accuracy** and select **Validation only** to check the reported results.

## References and acknowledgment

- [Forecasting: Principles and Practice](https://otexts.com/fpp3/)

*OpenAI ChatGPT helped draft the Shiny code*
