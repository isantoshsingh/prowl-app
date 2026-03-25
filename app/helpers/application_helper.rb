module ApplicationHelper
  include Pagy::Frontend

  # Renders a <time> element that JavaScript converts to the browser's local timezone.
  # Falls back to the UTC-formatted string if JS is disabled.
  # Use date_only: true for dates without time (e.g., trial expiration).
  def local_time(timestamp, format: "%B %d, %Y at %H:%M", date_only: false)
    return "" if timestamp.blank?

    utc = timestamp.utc
    css_class = date_only ? "local-time local-time-date" : "local-time"
    content_tag(:time, utc.strftime(format), datetime: utc.iso8601, class: css_class)
  end

  def pagy_tailwind_nav(pagy)
    return "" unless pagy.pages > 1

    link_class = "px-3 py-2 text-sm border border-gray-300 text-gray-700 hover:bg-gray-50 rounded-md"
    active_class = "px-3 py-2 text-sm border border-blue-500 bg-blue-600 text-white rounded-md"
    disabled_class = "px-3 py-2 text-sm border border-gray-200 text-gray-300 rounded-md cursor-not-allowed"

    html = +""
    html << '<nav class="flex justify-center mt-6"><ul class="flex items-center gap-1">'

    # Previous
    if pagy.prev
      html << %(<li><a href="#{pagy_url_for(pagy, pagy.prev)}" class="#{link_class}">&laquo; Prev</a></li>)
    else
      html << %(<li><span class="#{disabled_class}">&laquo; Prev</span></li>)
    end

    # Page numbers
    pagy.series.each do |item|
      case item
      when Integer
        html << %(<li><a href="#{pagy_url_for(pagy, item)}" class="#{link_class}">#{item}</a></li>)
      when String
        html << %(<li><span class="#{active_class}">#{item}</span></li>)
      when :gap
        html << %(<li><span class="px-2 py-2 text-sm text-gray-400">&hellip;</span></li>)
      end
    end

    # Next
    if pagy.next
      html << %(<li><a href="#{pagy_url_for(pagy, pagy.next)}" class="#{link_class}">Next &raquo;</a></li>)
    else
      html << %(<li><span class="#{disabled_class}">Next &raquo;</span></li>)
    end

    html << "</ul></nav>"
    html.html_safe
  end
end
