library(shiny)
library(bslib)
library(fpp3)
library(readr)
library(urca)

# Preserve missing observations in the source data.
wide <- read_csv("data/AustralianWines.csv", na = "*", show_col_types = FALSE) |>
  rename_with(trimws)
varieties <- c("Fortified", "Red", "Rose", "Sparkling", "Sweet white", "Dry white")
names(wide) <- sub("^sparkling$", "Sparkling", names(wide))
wine <- wide |>
  mutate(Month = yearmonth(as.Date(paste0("01-", Month), "%d-%b-%y"))) |>
  pivot_longer(all_of(varieties), names_to = "Varietal", values_to = "Sales") |>
  as_tsibble(index = Month, key = Varietal)

model_names <- c("TSLM", "ETS", "ARIMA")
month_label <- function(x) format(as.Date(x), "%b %Y")

# Keep every monthly index in training. Use earlier observations only.
prepare_training <- function(data) {
  data |> group_by(Varietal) |> fill(Sales, .direction = "down") |> ungroup()
}

fit_models <- function(training) {
  training |> model(
    TSLM = TSLM(Sales ~ trend() + season()),
    ETS = ETS(Sales),
    ARIMA = ARIMA(Sales),
    .safely = FALSE
  )
}

# Compute separately sized evaluation and user-selected forecast windows.
run_analysis <- function(data, cutoff, horizon) {
  training <- data |> filter(Month <= cutoff) |> prepare_training()
  validation <- data |> filter(Month > cutoff)
  fits <- fit_models(training)
  validation_fc <- forecast(fits, h = n_distinct(validation$Month))
  display_fc <- forecast(fits, h = horizon)

  specs <- bind_rows(lapply(model_names, function(name) {
    tibble(Varietal = fits$Varietal, Model = name,
           Specification = vapply(fits[[name]], format, character(1)))
  })) |>
    mutate(Specification = if_else(Model == "TSLM", "Linear trend + month-of-year seasonality", Specification))

  # accuracy() scores fitted values and forecasts on the original sales scale.
  train_scores <- fabletools::accuracy(fits, measures = list(RMSE = RMSE, MAE = MAE, MAPE = MAPE))
  test_scores <- fabletools::accuracy(validation_fc, data,
                          measures = list(RMSE = RMSE, MAE = MAE, MAPE = MAPE))
  scores <- bind_rows(
    mutate(train_scores, Window = "Training"),
    mutate(test_scores, Window = "Validation")
  ) |>
    select(Varietal, Window, Model = .model, RMSE, MAE, MAPE) |>
    mutate(Window = factor(Window, levels = c("Training", "Validation"))) |>
    arrange(Varietal, Window, RMSE)
  list(training = training, validation = validation, forecast = display_fc,
       observed = data, specifications = specs, scores = scores)
}

style_plot <- function(p) {
  p + theme_minimal(base_size = 13) +
    theme(panel.grid.minor = element_blank(),
          panel.grid.major.x = element_blank(),
          strip.text = element_text(face = "bold", hjust = 0),
          plot.title.position = "plot",
          legend.position = "bottom")
}

plot_forecasts <- function(result, cutoff, models = model_names, recent = 24L) {
  fc <- result$forecast |> as_tibble() |> filter(.model %in% models)
  distribution <- fc$Sales
  interval <- function(prob) vapply(distribution, function(d) as.numeric(quantile(d, prob)), numeric(1))
  fc <- fc |>
    mutate(Date = as.Date(Month), Lower95 = interval(.025), Upper95 = interval(.975),
           Lower80 = interval(.10), Upper80 = interval(.90),
           Model = factor(.model, levels = model_names))

  actual <- result$observed |> as_tibble() |>
    filter(Month > cutoff - recent, Month <= max(fc$Month)) |>
    mutate(Date = as.Date(Month))
  # Repeat the observed series in each model panel, with a light stroke.
  actual <- actual |> crossing(Model = factor(models, levels = model_names))

  one_month <- n_distinct(fc$Date) == 1L
  intervals <- if (one_month) {
    # A ribbon has no width when only one month is forecast.
    list(
      geom_linerange(aes(ymin = Lower95, ymax = Upper95, colour = "95% prediction interval"), linewidth = 1.9),
      geom_linerange(aes(ymin = Lower80, ymax = Upper80, colour = "80% prediction interval"), linewidth = 2.5)
    )
  } else {
    list(
      geom_ribbon(aes(ymin = Lower95, ymax = Upper95, fill = "95% prediction interval"), alpha = .35),
      geom_ribbon(aes(ymin = Lower80, ymax = Upper80, fill = "80% prediction interval"), alpha = .65),
      geom_line(aes(y = .mean, colour = "Forecast"), linewidth = .85)
    )
  }

  chart <- ggplot(fc, aes(Date)) +
    intervals +
    geom_line(data = actual, aes(y = Sales, colour = "Actual sales"), linewidth = .50, na.rm = TRUE) +
    geom_vline(xintercept = as.Date(cutoff), colour = "#98817e", linetype = "dashed") +
    geom_point(aes(y = .mean, colour = "Forecast"), size = 1.2) +
    facet_grid(Varietal ~ Model, scales = "free_y") +
    scale_colour_manual(NULL, values = c("Actual sales" = "#58535b", Forecast = "#8d3152",
                                  "80% prediction interval" = "#ce7895", "95% prediction interval" = "#e5aec1")) +
    scale_y_continuous(labels = scales::label_comma()) +
    scale_x_date(date_breaks = "1 year", date_labels = "%Y", expand = expansion(mult = .02)) +
    labs(x = NULL, y = "Sales (thousand liters)")
  if (!one_month) {
    chart <- chart + scale_fill_manual(NULL, values = c(
      "80% prediction interval" = "#ce7895", "95% prediction interval" = "#e5aec1"
    ))
  }
  style_plot(chart)
}

# Keep each control and its explanation together.
setting <- function(input, explanation) {
  div(class = "setting", input, tags$small(explanation))
}

ui <- page_navbar(
  title = span("Australian Wine Sales", class = "app-title"),
  theme = bs_theme(version = 5, bg = "#fbf8f5", fg = "#201827", primary = "#8d3152",
                   base_font = "system-ui", heading_font = "Georgia"),
  header = tags$head(tags$style(HTML("
    .app-title { font-family: Georgia, serif; font-weight: 700; }
    .masthead { padding: 1.4rem; margin-bottom: 1rem; border-radius: 12px; background: #f1e5e8; }
    .masthead h1 { font-size: clamp(1.7rem, 4vw, 2.4rem); }
    .periods { display: flex; flex-wrap: wrap; gap: .5rem; }
    .periods span { background: #fff9fb; border-radius: 6px; padding: .35rem .6rem; }
    .setting { margin-bottom: .8rem; }
    .setting .form-group { margin-bottom: .2rem; }
    .setting small { display: block; color: #655765; line-height: 1.35; }
    .about { max-width: 740px; margin: 2rem auto; padding: 0 1rem; }
    .about h2 { font-size: 1.25rem; margin-top: 1.4rem; }
    .tab-pane { overflow-x: auto; }
    @media(max-width: 700px) { #forecast { min-width: 620px; } }
  "))),
  nav_panel("Forecast lab",
    layout_sidebar(
      sidebar = sidebar(
        title = "Set up your comparison", width = 322,
        setting(selectizeInput("varieties", "Wine types", choices = varieties,
                              selected = c("Fortified", "Red"), multiple = TRUE),
                "Pick one wine to study or several to compare."),
        setting(dateRangeInput("dates", "Sales dates", start = min(as.Date(wine$Month)),
                               end = max(as.Date(wine$Month)), min = min(as.Date(wine$Month)),
                               max = max(as.Date(wine$Month)), format = "yyyy-mm", startview = "year"),
                "Choose which months to include. Use at least 37 months."),
        setting(uiOutput("split_control"),
                "Models learn from sales up to this month. Later sales are used to check the forecasts."),
        setting(sliderInput("horizon", "Months to predict", min = 1, max = 24, value = 12),
                "Choose how far ahead to look on the forecast chart."),
        setting(checkboxGroupInput("models", "Show these models", choices = model_names,
                                   selected = model_names, inline = TRUE),
                "Show or hide model charts. The score table still includes all three."),
        setting(selectInput("recent", "Past sales on forecast chart",
                            c("12 months" = 12, "24 months" = 24, "36 months" = 36), selected = 24),
                "Show more past sales for context or fewer to focus on the forecast.")
      ),
      div(class = "masthead",
          h1("Compare wine sales forecasts"),
          p("See what sold, when sales tend to rise, and how closely each model predicts later sales."),
          uiOutput("summary")),
      navset_card_tab(
        nav_panel("Forecast",
          p("Dark lines show actual sales. Pink shows predictions and the range of likely sales. The dashed line marks the end of training."),
          plotOutput("forecast", height = "auto", fill = FALSE),
          downloadButton("download_plot", "Save chart")),
        nav_panel("Sales history",
          setting(selectInput("sales_view", "Show sales by", c("Timeline" = "timeline", "Month of the year" = "month")),
                  "Use the timeline to see changes over time or the monthly view to spot recurring peaks."),
          plotOutput("overview", height = "auto", fill = FALSE)),
        nav_panel("Accuracy",
          setting(selectInput("score_window", "Show scores for",
                              c("Both periods" = "All", "Validation only" = "Validation", "Training only" = "Training")),
                  "Use validation to compare how well the models predict later sales."),
          p("Lower scores are better. RMSE gives larger misses more weight. MAE is the average size of a miss. RMSE and MAE are in thousand liters. MAPE shows the average size as a percentage."),
          tableOutput("metrics"),
          downloadButton("download_metrics", "Save all scores")),
        nav_panel("Model specifications",
          p("See the structure chosen for each model and wine type."),
          tableOutput("specs"))
      )
    )
  ),
  nav_panel("About",
    div(class = "about",
      h1("About the forecasts"),
      h2("Data"),
      p("Monthly Australian wine sales, 1980–1994, measured in thousand liters. Source: the AustralianWines.csv file supplied for ADS-506."),
      tags$a(href = "https://sandiego.instructure.com/courses/32521/files/4971419?wrap=1", "Course dataset"),
      h2("Models and evaluation"),
      p("TSLM uses a straight-line trend and a pattern for each month of the year. ETS estimates the sales level, trend, and seasonal pattern. ARIMA uses past patterns in sales and forecast errors. ETS and ARIMA choose their settings from the training period."),
      p("For a missing training month, the model uses the last known sales value. A missing month in the test period is skipped when scoring. The shaded bands show the 80% and 95% prediction ranges. Scores use the whole test period, even when the chart shows fewer months."),
      h2("Reproduce the data story"),
      p("Select Fortified and Red, use January 1980 to December 1994, end training in December 1993, set the forecast to 12 months, and select all three models. Open Accuracy for the ranking and Forecast for the chart."),
      h2("Code and sources"),
      p("Built with Shiny, bslib, and tidyverts (fpp3). OpenAI ChatGPT helped draft the app code and documentation."),
      tags$a(href = "https://otexts.com/fpp3/", "Forecasting: Principles and Practice")
    )
  )
)

server <- function(input, output, session) {
  selected_data <- reactive({
    validate(need(length(input$varieties) > 0, "Select at least one wine variety."))
    req(input$dates)
    wine |> filter(Varietal %in% input$varieties,
                   Month >= yearmonth(input$dates[1]), Month <= yearmonth(input$dates[2]))
  })

  eligible_months <- reactive({
    req(input$dates)
    months <- sort(unique(wine$Month[wine$Month >= yearmonth(input$dates[1]) &
                                       wine$Month < yearmonth(input$dates[2])]))
    # Leave 36 months for training and at least one month for validation.
    months[seq_along(months) >= 36L]
  })

  output$split_control <- renderUI({
    months <- eligible_months()
    if (!length(months)) return(tags$p("Choose a date range with at least 37 months."))
    choices <- setNames(as.character(as.Date(months)), month_label(months))
    previous <- isolate(input$cutoff)
    selected <- if (isTruthy(previous) && previous %in% choices) previous else
      if ("1993-12-01" %in% choices) "1993-12-01" else tail(choices, 1)
    selectInput("cutoff", "Last training month", choices, selected = selected)
  })

  analysis <- reactive({
    data <- selected_data()
    validate(need(length(eligible_months()) > 0, "Choose a date range with at least 37 months."))
    req(input$cutoff, input$horizon)
    cutoff <- yearmonth(as.Date(input$cutoff))
    validate(need(cutoff %in% eligible_months(), "Select a valid last training month."))
    train_ready <- data |> filter(Month <= cutoff) |> prepare_training()
    observed <- data |> filter(Month > cutoff) |>
      as_tibble() |> group_by(Varietal) |> summarise(n = sum(!is.na(Sales)), .groups = "drop")
    validate(need(!anyNA(train_ready$Sales), "Choose an earlier start month so training starts with observed sales."),
             need(all(observed$n > 0), "Choose a split with at least one observed validation month per variety."))
    tryCatch(run_analysis(data, cutoff, input$horizon),
             error = function(e) validate(need(FALSE, paste("These settings could not be fitted.", conditionMessage(e)))))
  })

  output$summary <- renderUI({
    result <- analysis()
    div(class = "periods",
        span(strong("Training"), paste(month_label(min(result$training$Month)), "to", month_label(max(result$training$Month)))),
        span(strong("Validation"), paste(month_label(min(result$validation$Month)), "to", month_label(max(result$validation$Month)))))
  })

  forecast_chart <- reactive({
    result <- analysis()
    validate(need(length(input$models) > 0, "Select at least one model to display."))
    plot_forecasts(result, max(result$training$Month), input$models, as.integer(input$recent))
  })

  output$forecast <- renderPlot(forecast_chart(), height = function() max(360, 205 * length(input$varieties) + 80), res = 96)

  output$overview <- renderPlot({
    data <- selected_data()
    chart <- if (identical(input$sales_view, "month")) {
      data |> mutate(CalendarMonth = factor(month(Month), levels = 1:12, labels = month.abb)) |>
        ggplot(aes(CalendarMonth, Sales)) +
        geom_boxplot(fill = "#ecd3dc", colour = "#8d3152", na.rm = TRUE)
    } else {
      ggplot(data, aes(as.Date(Month), Sales)) +
        geom_line(colour = "#8d3152", linewidth = .65, na.rm = TRUE)
    }
    chart <- chart + facet_wrap(vars(Varietal), scales = "free_y", ncol = 2) +
      scale_y_continuous(labels = scales::label_comma()) +
      labs(x = NULL, y = "Sales (thousand liters)")
    style_plot(chart)
  }, height = function() max(350, 200 * ceiling(length(input$varieties) / 2) + 60), res = 96)

  output$metrics <- renderTable({
    scores <- analysis()$scores
    if (isTruthy(input$score_window) && input$score_window != "All") {
      scores <- filter(scores, Window == input$score_window)
    }
    scores
  }, digits = 2, striped = TRUE, spacing = "s")
  output$specs <- renderTable(analysis()$specifications, striped = TRUE, spacing = "s")

  output$download_plot <- downloadHandler("wine-forecast.png", function(file) {
    ggsave(file, forecast_chart(), device = "png", width = 10, height = max(4, 1.9 * length(input$varieties) + 1), dpi = 180)
  })
  output$download_metrics <- downloadHandler("wine-accuracy.csv", function(file) {
    write_csv(analysis()$scores, file)
  })
}

shinyApp(ui, server)
