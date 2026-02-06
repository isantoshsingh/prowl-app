# frozen_string_literal: true

module Detectors
  # AddToCartDetector verifies the Add-to-Cart button exists, is visible,
  # enabled, and is part of a valid product form.
  #
  # Validation checks:
  #   1. Button exists in DOM (multiple selector strategies)
  #   2. Button is visible (offsetHeight > 0, not display:none)
  #   3. Button is not disabled
  #   4. Button has click handler or is inside a valid form
  #   5. Product form exists with valid action
  #   6. Button text contains expected content
  #
  # Horizon theme patterns:
  #   - Uses <product-form> custom element
  #   - Button: form[action="/cart/add"] button[type="submit"]
  #   - Class patterns: .product-form__submit, .shopify-payment-button
  #
  class AddToCartDetector < BaseDetector
    # Selectors ordered by specificity - Horizon theme first, then common patterns
    ATC_BUTTON_SELECTORS = [
      'product-form button[type="submit"]',
      'form[action*="/cart/add"] button[type="submit"]',
      'button[name="add"]',
      '.product-form__submit',
      '.product-form__cart-submit',
      '#AddToCart',
      '#add-to-cart',
      '[data-add-to-cart]',
      'button.add-to-cart',
      '.add-to-cart-button',
      'input[type="submit"][name="add"]'
    ].freeze

    PRODUCT_FORM_SELECTORS = [
      'product-form form[action*="/cart/add"]',
      'form[action*="/cart/add"]',
      'form.product-form',
      'form[data-product-form]',
      'form.shopify-product-form',
      '#product-form',
      '#AddToCartForm'
    ].freeze

    def check_name
      "add_to_cart"
    end

    private

    def run_detection
      result = evaluate(atc_detection_script)

      if result.nil?
        return inconclusive_result("Could not evaluate Add-to-Cart detection script")
      end

      button_found = record_validation(result["button_found"])
      button_visible = record_validation(result["button_visible"])
      button_enabled = record_validation(result["button_enabled"])
      form_valid = record_validation(result["form_valid"])
      has_click_handler = record_validation(result["has_click_handler"] || result["form_valid"])
      text_reasonable = record_validation(reasonable_button_text?(result["button_text"]))

      # Check for out-of-stock scenario - disabled button is expected
      if result["button_found"] && !result["button_enabled"] && sold_out_product?(result)
        return pass_result(
          message: "Add-to-Cart button found but disabled (product appears sold out)",
          confidence: 0.9,
          technical_details: {
            selector_used: result["selector_used"],
            button_text: result["button_text"],
            sold_out: true
          },
          evidence: {
            button_found: true,
            button_visible: result["button_visible"],
            button_disabled_reason: "sold_out"
          }
        )
      end

      if button_found && button_visible && button_enabled && form_valid
        pass_result(
          message: "Add-to-Cart button is present, visible, and functional",
          technical_details: {
            selector_used: result["selector_used"],
            button_text: result["button_text"],
            form_action: result["form_action"]
          },
          evidence: {
            button_found: true,
            button_visible: true,
            button_enabled: true,
            form_valid: true,
            has_click_handler: result["has_click_handler"]
          }
        )
      elsif !button_found
        fail_result(
          message: "Add-to-Cart button could not be found on the page",
          confidence: [calculated_confidence, 0.8].max,
          technical_details: {
            selectors_tried: ATC_BUTTON_SELECTORS,
            form_found: result["form_found"]
          },
          evidence: {
            button_found: false,
            selectors_tried_count: ATC_BUTTON_SELECTORS.length
          },
          suggestions: [
            "Verify the product form exists in your theme's product template",
            "Check that the Add-to-Cart button uses standard Shopify markup",
            "Ensure no JavaScript errors are preventing the button from rendering"
          ]
        )
      elsif !button_visible
        fail_result(
          message: "Add-to-Cart button exists but is not visible to customers",
          technical_details: {
            selector_used: result["selector_used"],
            visibility_details: result["visibility_details"]
          },
          evidence: {
            button_found: true,
            button_visible: false,
            display: result.dig("visibility_details", "display"),
            visibility: result.dig("visibility_details", "visibility")
          },
          suggestions: [
            "Check CSS rules that may be hiding the button",
            "Verify no theme customization is hiding the product form"
          ]
        )
      else
        warning_result(
          message: "Add-to-Cart button found with potential issues",
          technical_details: {
            selector_used: result["selector_used"],
            button_text: result["button_text"],
            button_enabled: result["button_enabled"],
            form_valid: result["form_valid"]
          },
          evidence: {
            button_found: button_found,
            button_visible: button_visible,
            button_enabled: button_enabled,
            form_valid: form_valid
          },
          suggestions: [
            "Review the product form configuration in your theme"
          ]
        )
      end
    end

    def sold_out_product?(result)
      text = result["button_text"].to_s.downcase
      text.include?("sold out") ||
        text.include?("unavailable") ||
        text.include?("out of stock") ||
        text.include?("notify me")
    end

    def reasonable_button_text?(text)
      return false if text.blank?
      normalized = text.to_s.downcase.strip
      normalized.match?(/add to cart|add to bag|buy now|purchase|sold out|unavailable|notify|pre-?order|subscribe/i) ||
        normalized.length.between?(3, 50)
    end

    def atc_detection_script
      button_selectors_js = ATC_BUTTON_SELECTORS.map { |s| "'#{s}'" }.join(", ")
      form_selectors_js = PRODUCT_FORM_SELECTORS.map { |s| "'#{s}'" }.join(", ")

      <<~JAVASCRIPT
        () => {
          const buttonSelectors = [#{button_selectors_js}];
          const formSelectors = [#{form_selectors_js}];

          // Find ATC button
          let button = null;
          let selectorUsed = null;
          for (const sel of buttonSelectors) {
            const el = document.querySelector(sel);
            if (el) {
              button = el;
              selectorUsed = sel;
              break;
            }
          }

          // Find product form
          let form = null;
          for (const sel of formSelectors) {
            const el = document.querySelector(sel);
            if (el) {
              form = el;
              break;
            }
          }

          // If no button found via selectors, try text-based search
          if (!button) {
            const allButtons = document.querySelectorAll('button, input[type="submit"]');
            for (const btn of allButtons) {
              const text = (btn.textContent || btn.value || '').toLowerCase().trim();
              if (text.includes('add to cart') || text.includes('add to bag') || text.includes('buy now')) {
                button = btn;
                selectorUsed = 'text-search';
                break;
              }
            }
          }

          if (!button) {
            return {
              button_found: false,
              button_visible: false,
              button_enabled: false,
              button_text: null,
              selector_used: null,
              form_found: !!form,
              form_valid: false,
              form_action: form ? form.action : null,
              has_click_handler: false,
              visibility_details: null
            };
          }

          // Visibility checks
          const style = window.getComputedStyle(button);
          const rect = button.getBoundingClientRect();
          const isVisible = (
            style.display !== 'none' &&
            style.visibility !== 'hidden' &&
            style.opacity !== '0' &&
            rect.width > 0 &&
            rect.height > 0
          );

          // Determine if button is in a valid form
          const parentForm = button.closest('form');
          const formAction = parentForm ? parentForm.getAttribute('action') : null;
          const formValid = !!(parentForm && formAction && formAction.includes('/cart/add'));

          // Check for click handlers
          const hasClickHandler = button.onclick !== null ||
            button.hasAttribute('onclick') ||
            formValid; // Being inside a valid form counts

          return {
            button_found: true,
            button_visible: isVisible,
            button_enabled: !button.disabled && !button.hasAttribute('aria-disabled'),
            button_text: (button.textContent || button.value || '').trim().substring(0, 100),
            selector_used: selectorUsed,
            form_found: !!(form || parentForm),
            form_valid: formValid,
            form_action: formAction,
            has_click_handler: hasClickHandler,
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
