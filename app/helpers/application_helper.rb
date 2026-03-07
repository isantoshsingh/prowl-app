module ApplicationHelper
  # Renders a <time> element that JavaScript converts to the browser's local timezone.
  # Falls back to the UTC-formatted string if JS is disabled.
  # Use date_only: true for dates without time (e.g., trial expiration).
  def local_time(timestamp, format: "%B %d, %Y at %H:%M", date_only: false)
    return "" if timestamp.blank?

    utc = timestamp.utc
    css_class = date_only ? "local-time local-time-date" : "local-time"
    content_tag(:time, utc.strftime(format), datetime: utc.iso8601, class: css_class)
  end
end
