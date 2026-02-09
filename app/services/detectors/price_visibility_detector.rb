# frozen_string_literal: true

module Detectors
  # PriceVisibilityDetector verifies that the product price is visible
  # and correctly formatted on the page.
  #
  # Validation checks:
  #   1. Price element exists in DOM (multiple selector strategies)
  #   2. Price text is not empty or placeholder
  #   3. Price element is visible (not hidden by CSS)
  #   4. Price format looks reasonable (contains currency or numbers)
  #   5. Handle compare-at-price and sale prices
  #
  # Horizon theme patterns:
  #   - .price container with .price__regular and .price__sale
  #   - .price-item--regular, .price-item--sale classes
  #   - Uses <money> or span.money elements
  #
  class PriceVisibilityDetector < BaseDetector
    PRICE_SELECTORS = [
      ".price",
      ".price__regular",
      ".price__sale",
      ".product__price",
      ".product-price",
      ".price-item",
      ".price-item--regular",
      ".price-item--sale",
      "[data-price]",
      "[data-product-price]",
      ".money",
      "span.money",
      ".product-single__price",
      ".product__meta .price",
      "#ProductPrice",
      "#productPrice",
      ".price-container",
      ".product-info__price"
    ].freeze

    # Regex to match common price formats
    PRICE_FORMAT = /(?:\$|€|£|¥|₹|C\$|A\$|USD|EUR|GBP|CAD|AUD)\s*[\d,]+\.?\d*|[\d,]+\.?\d*\s*(?:\$|€|£|¥|₹|USD|EUR|GBP|CAD|AUD)/

    def check_name
      "price_visibility"
    end

    private

    def run_detection
      result = evaluate(price_detection_script)

      if result.nil?
        return inconclusive_result("Could not evaluate price detection script")
      end

      price_found = record_validation(result["price_found"])
      price_visible = record_validation(result["price_visible"])
      price_not_empty = record_validation(result["price_text"].present? && result["price_text"].strip.length > 0)
      price_formatted = record_validation(valid_price_format?(result["price_text"]))
      not_placeholder = record_validation(!placeholder_price?(result["price_text"]))

      if price_found && price_visible && price_formatted
        pass_result(
          message: "Product price is visible and correctly formatted",
          technical_details: {
            selector_used: result["selector_used"],
            price_text: result["price_text"],
            has_compare_at_price: result["has_compare_at_price"],
            has_sale_price: result["has_sale_price"]
          },
          evidence: {
            price_found: true,
            price_visible: true,
            price_text: result["price_text"],
            price_count: result["price_element_count"]
          }
        )
      elsif !price_found
        fail_result(
          message: "Product price could not be found on the page",
          confidence: [calculated_confidence, 0.8].max,
          technical_details: {
            selectors_tried: PRICE_SELECTORS
          },
          evidence: {
            price_found: false,
            selectors_tried_count: PRICE_SELECTORS.length
          },
          suggestions: [
            "Verify the price element exists in your product template",
            "Check that no app or theme customization is removing the price",
            "Ensure the product has a price set in Shopify admin"
          ]
        )
      elsif !price_visible
        fail_result(
          message: "Product price exists but is not visible to customers",
          technical_details: {
            selector_used: result["selector_used"],
            visibility_details: result["visibility_details"]
          },
          evidence: {
            price_found: true,
            price_visible: false,
            display: result.dig("visibility_details", "display"),
            visibility: result.dig("visibility_details", "visibility")
          },
          suggestions: [
            "Check CSS rules that may be hiding the price",
            "Verify no theme customization is hiding the price element"
          ]
        )
      elsif !price_formatted
        warning_result(
          message: "Product price found but format may be incorrect",
          technical_details: {
            selector_used: result["selector_used"],
            price_text: result["price_text"]
          },
          evidence: {
            price_found: true,
            price_visible: true,
            price_text: result["price_text"],
            format_valid: false
          },
          suggestions: [
            "Verify the price is displaying with proper currency formatting",
            "Check if a currency conversion app is causing display issues"
          ]
        )
      else
        warning_result(
          message: "Product price detected with potential issues",
          technical_details: {
            price_text: result["price_text"],
            selector_used: result["selector_used"]
          },
          evidence: {
            price_found: price_found,
            price_visible: price_visible,
            price_formatted: price_formatted
          }
        )
      end
    end

    def valid_price_format?(text)
      return false if text.blank?
      text.strip.match?(PRICE_FORMAT) || text.strip.match?(/\d+[.,]\d{2}/)
    end

    def placeholder_price?(text)
      return true if text.blank?
      normalized = text.to_s.strip.downcase
      normalized == "$0.00" ||
        normalized == "0.00" ||
        normalized == "price" ||
        normalized.include?("loading") ||
        normalized.include?("calculating")
    end

    def price_detection_script
      selectors_js = PRICE_SELECTORS.map { |s| "'#{s}'" }.join(", ")

      <<~JAVASCRIPT
        () => {
          const selectors = [#{selectors_js}];

          let priceEl = null;
          let selectorUsed = null;

          // Try each selector
          for (const sel of selectors) {
            const el = document.querySelector(sel);
            if (el) {
              const text = el.textContent.trim();
              // Only accept if it has actual price content
              if (text.length > 0 && text.match(/[\\d$€£¥₹]/)) {
                priceEl = el;
                selectorUsed = sel;
                break;
              }
            }
          }

          // Fallback: search for elements with price-like text content
          if (!priceEl) {
            const allElements = document.querySelectorAll('span, div, p, bdi');
            for (const el of allElements) {
              const text = el.textContent.trim();
              if (text.match(/^[\\s]*[\\$€£¥₹C\\$A\\$]?[\\s]*[\\d,]+\\.\\d{2}[\\s]*$/) && el.children.length <= 2) {
                const style = window.getComputedStyle(el);
                if (style.display !== 'none' && style.visibility !== 'hidden') {
                  priceEl = el;
                  selectorUsed = 'text-search';
                  break;
                }
              }
            }
          }

          if (!priceEl) {
            return {
              price_found: false,
              price_visible: false,
              price_text: null,
              selector_used: null,
              price_element_count: 0,
              has_compare_at_price: false,
              has_sale_price: false,
              visibility_details: null
            };
          }

          // Visibility checks
          const style = window.getComputedStyle(priceEl);
          const rect = priceEl.getBoundingClientRect();
          const isVisible = (
            style.display !== 'none' &&
            style.visibility !== 'hidden' &&
            style.opacity !== '0' &&
            rect.width > 0 &&
            rect.height > 0
          );

          // Count total price elements
          let priceCount = 0;
          for (const sel of selectors) {
            priceCount += document.querySelectorAll(sel).length;
          }

          // Check for compare-at/sale pricing
          const hasCompareAt = !!(
            document.querySelector('.price__sale') ||
            document.querySelector('.price-item--sale') ||
            document.querySelector('[data-compare-price]') ||
            document.querySelector('.compare-at-price') ||
            document.querySelector('s.price-item')
          );

          const hasSalePrice = !!(
            document.querySelector('.price--on-sale') ||
            document.querySelector('.price--sale') ||
            document.querySelector('.price-item--sale')
          );

          return {
            price_found: true,
            price_visible: isVisible,
            price_text: priceEl.textContent.trim().substring(0, 50),
            selector_used: selectorUsed,
            price_element_count: priceCount,
            has_compare_at_price: hasCompareAt,
            has_sale_price: hasSalePrice,
            visibility_details: {
              display: style.display,
              visibility: style.visibility,
              opacity: style.opacity,
              width: rect.width,
              height: rect.height
            }
          };
        }
      JAVASCRIPT
    end
  end
end
