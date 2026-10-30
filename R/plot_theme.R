# plot_theme.R
#
# Shared chart style for every figure in this project, matching my other
# portfolio projects: a bold headline that states the finding, a grey
# subtitle, direct labels instead of legends, and a source note. Sourced by
# the analysis scripts; not run on its own.

library(ggplot2)

col_indigo   <- "#1D1B4C"  # development cohort (Rotterdam) / main series
col_marigold <- "#F2A900"  # validation cohort (GBSG 2) / comparison
col_mid      <- "#B9B8C8"  # context series and reference lines
col_text     <- "#1F1F1F"
col_muted    <- "#6B6B6B"
col_grid     <- "#E6E6E6"

cohort_cols <- c(
  "Rotterdam (development)" = col_indigo,
  "GBSG 2 (validation)"     = col_marigold
)

source_note <- "Source: Rotterdam tumour bank and German Breast Cancer Study Group (GBSG 2), via the survival R package."

theme_project <- function(base_size = 12) {
  theme_minimal(base_size = base_size) +
    theme(
      plot.title = element_text(face = "bold", colour = col_text, size = rel(1.15),
                                margin = margin(b = 4)),
      plot.subtitle = element_text(colour = col_muted, margin = margin(b = 12)),
      plot.caption = element_text(colour = col_muted, size = rel(0.75), hjust = 0,
                                  margin = margin(t = 10)),
      plot.title.position = "plot",
      plot.caption.position = "plot",
      axis.title = element_text(colour = col_muted, size = rel(0.85)),
      axis.text = element_text(colour = col_muted),
      panel.grid.major = element_line(colour = col_grid, linewidth = 0.3),
      panel.grid.minor = element_blank(),
      legend.position = "none",
      plot.margin = margin(14, 18, 10, 14),
      plot.background = element_rect(fill = "white", colour = NA)
    )
}

wrap <- function(text, width = 80) paste(strwrap(text, width), collapse = "\n")

save_figure <- function(plot, name, width = 8, height = 5) {
  # Wrap long titles and subtitles so they never run off the image
  if (!is.null(plot$labels$title)) plot$labels$title <- wrap(plot$labels$title, 72)
  if (!is.null(plot$labels$subtitle)) plot$labels$subtitle <- wrap(plot$labels$subtitle, 95)
  if (!is.null(plot$labels$caption)) plot$labels$caption <- wrap(plot$labels$caption, 120)
  dir.create(file.path("output", "figures"), recursive = TRUE, showWarnings = FALSE)
  path <- file.path("output", "figures", paste0(name, ".png"))
  ggsave(path, plot, width = width, height = height, dpi = 200, bg = "white")
  message("  saved ", path)
  invisible(path)
}
