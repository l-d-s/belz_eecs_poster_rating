plotting_pdf_device <- function() {
  if (capabilities("cairo")) grDevices::cairo_pdf else grDevices::pdf
}

plotting_font_family <- function() {
  if (!capabilities("cairo")) {
    warning("Cairo is unavailable; using the standard PDF device and sans-serif font.")
    return("sans")
  }
  if (!any(tolower(systemfonts::system_fonts()$family) == "arial")) {
    warning("Arial is unavailable; using a portable sans-serif font.")
    return("sans")
  }
  "Arial"
}

theme_clean <- function(font_family = plotting_font_family()) {
  `%+replace%` <- ggplot2::`%+replace%`

  cowplot::theme_cowplot(font_size = 16) %+replace%
    ggplot2::theme(
      text = ggplot2::element_text(family = font_family),
      axis.text = ggplot2::element_text(size = 14),
      axis.title = ggplot2::element_text(size = 16),
      legend.text = ggplot2::element_text(size = 15),
      legend.title = ggplot2::element_text(size = 16),
      strip.text = ggplot2::element_text(size = 17),
      strip.background = ggplot2::element_blank(),
      strip.text.y = ggplot2::element_text(angle = 0),
      axis.title.y = ggplot2::element_text(
        angle = 0,
        hjust = 0,
        vjust = 0.5,
        margin = ggplot2::margin(r = 5, unit = "pt")
      ),
      title = ggplot2::element_text(size = 18, face = "plain")
    )
}

stat_ecdf_pointline <- function(...) {
  list(
    ggplot2::stat_ecdf(..., geom = "line", alpha = 0.6, pad = FALSE),
    ggplot2::stat_ecdf(..., geom = "point", pad = FALSE)
  )
}

strict_01 <- function(x) ifelse(x %in% c(0, 1), NA, x)

gg_hist <- function(data, x_var, n_bins = 30, breaks = NULL, boundary = NULL, ...) {
  ggplot2::ggplot(data, ggplot2::aes({{ x_var }})) +
    theme_clean() +
    ggplot2::geom_histogram(
      bins = n_bins, color = "white", breaks = breaks, boundary = boundary, ...
    ) +
    ggplot2::scale_y_continuous(
      expand = ggplot2::expansion(c(0, 0.1)),
      limits = c(0, NA),
      name = "",
      breaks = scales::breaks_pretty(4)
    ) +
    ggplot2::theme(axis.line.y = ggplot2::element_blank())
}

gg_count <- function(data, x_var, geom = "bar", ...) {
  if (geom == "bar") {
    y_axis <- ggplot2::scale_y_continuous(
      expand = ggplot2::expansion(c(0, 0.1)),
      limits = c(0, NA),
      name = ""
    )
  } else {
    y_axis <- list()
  }

  ggplot2::ggplot(data, ggplot2::aes({{ x_var }})) +
    theme_clean() +
    ggplot2::stat_count(geom = geom, ...) +
    y_axis
}

gg_bin2d <- function(
  data,
  x,
  y,
  n_bins = 30,
  guide = TRUE,
  fill_scale = ggplot2::scale_fill_viridis_c(
    option = "inferno",
    trans = "log",
    end = 0.85,
    breaks = scales::breaks_log(n = 5),
    labels = round
  ),
  ...
) {
  if (guide) {
    guide <- ggplot2::geom_blank()
  } else {
    guide <- ggplot2::guides(fill = "none")
  }

  ggplot2::ggplot(data, ggplot2::aes({{ x }}, {{ y }})) +
    ggplot2::geom_bin2d(bins = n_bins, ...) +
    fill_scale +
    ggplot2::theme(aspect.ratio = 1) +
    guide
}

gg_scatter <- function(data, x, y, ...) {
  ggplot2::ggplot(data, ggplot2::aes({{ x }}, {{ y }})) +
    ggplot2::geom_point(...)
}
