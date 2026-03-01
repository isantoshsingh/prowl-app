# frozen_string_literal: true

module Detectors
  # AddToCartDetector verifies the full Add-to-Cart purchase flow works.
  #
  # Three-layer detection:
  #   Layer 1 (Structural): Does the cart form + submit button exist in DOM?
  #   Layer 2 (Interaction): Can we select a variant, click ATC, and verify cart updates?
  #   Layer 3 (AI): Visual confirmation via Gemini (handled by AiIssueAnalyzer, not here)
  #
  # All checks are language-independent — uses DOM attributes and Shopify platform
  # APIs (/cart.js, /cart/change.js) instead of button text matching.
  #
  # Scan depth modes:
  #   :quick — Layer 1 only (structural checks + variant selection attempt)
  #   :deep  — Layers 1 + 2 (full funnel: select variant → ATC → verify cart → cleanup)
  #
  class AddToCartDetector < BaseDetector
    # Selectors ordered by specificity — Shopify conventions first
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

    def initialize(browser_service, scan_depth: :quick)
      super(browser_service)
      @scan_depth = scan_depth
    end

    def check_name
      "add_to_cart"
    end

    private

    def run_detection
      # Layer 1: Structural check — does the form + button exist?
      structural = evaluate(atc_detection_script)

      if structural.nil?
        return inconclusive_result("Could not evaluate Add-to-Cart detection script")
      end

      button_found = structural["button_found"]
      button_visible = structural["button_visible"]
      button_enabled = structural["button_enabled"]
      form_valid = structural["form_valid"]

      # Record validations for confidence scoring
      record_validation(button_found)
      record_validation(button_visible)
      record_validation(form_valid)

      # Check for sold-out product (disabled button is expected)
      if button_found && !button_enabled && sold_out_text?(structural["button_text"])
        record_validation(true) # Disabled is expected for sold out
        return pass_result(
          message: "Add-to-Cart button found but disabled (product appears sold out)",
          confidence: 0.9,
          technical_details: {
            selector_used: structural["selector_used"],
            button_text: structural["button_text"],
            sold_out: true
          },
          evidence: {
            button_found: true,
            button_visible: button_visible,
            button_disabled_reason: "sold_out"
          }
        )
      end

      # If button found but disabled, try selecting a variant first
      if button_found && !button_enabled
        variant_result = browser_service.select_first_variant
        if variant_result[:selected]
          # Re-evaluate after variant selection
          structural = evaluate(atc_detection_script) || structural
          button_enabled = structural["button_enabled"]
        end
      end

      record_validation(button_enabled)

      # If button is now enabled (or was always enabled) + form is valid
      if button_found && button_visible && button_enabled && form_valid
        if @scan_depth == :deep
          # Layer 2: Full funnel test — actually click ATC and verify cart
          return run_funnel_test(structural)
        else
          # Quick scan: structural checks passed, button is functional
          return pass_result(
            message: "Add-to-Cart button is present, visible, and enabled",
            technical_details: {
              selector_used: structural["selector_used"],
              button_text: structural["button_text"],
              form_action: structural["form_action"]
            },
            evidence: {
              button_found: true,
              button_visible: true,
              button_enabled: true,
              form_valid: true,
              scan_depth: @scan_depth.to_s
            }
          )
        end
      end

      # Button not found at all
      unless button_found
        return fail_result(
          message: "Add-to-Cart button could not be found on the page",
          confidence: [calculated_confidence, 0.85].max,
          technical_details: {
            selectors_tried: ATC_BUTTON_SELECTORS,
            form_found: structural["form_found"]
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
      end

      # Button found but not visible
      unless button_visible
        return fail_result(
          message: "Add-to-Cart button exists but is not visible to customers",
          technical_details: {
            selector_used: structural["selector_used"],
            visibility_details: structural["visibility_details"]
          },
          evidence: {
            button_found: true,
            button_visible: false,
            display: structural.dig("visibility_details", "display"),
            visibility: structural.dig("visibility_details", "visibility")
          },
          suggestions: [
            "Check CSS rules that may be hiding the button",
            "Verify no theme customization is hiding the product form"
          ]
        )
      end

      # Button found + visible but still disabled after variant selection attempt
      fail_result(
        message: "Add-to-Cart button is present but not clickable — customers cannot add this product to cart",
        confidence: [calculated_confidence, 0.85].max,
        technical_details: {
          selector_used: structural["selector_used"],
          button_text: structural["button_text"],
          button_enabled: false,
          form_valid: form_valid,
          variant_selection_attempted: true
        },
        evidence: {
          button_found: true,
          button_visible: true,
          button_enabled: false,
          form_valid: form_valid
        },
        suggestions: [
          "Check that the Add-to-Cart button is not permanently disabled in your theme code",
          "Verify product variants are set up correctly in Shopify admin",
          "Check for JavaScript errors that may prevent the button from activating"
        ]
      )
    end

    # Layer 2: Full purchase funnel test
    # Clicks ATC, verifies cart updates, then cleans up
    def run_funnel_test(structural)
      # Read cart state before ATC
      cart_before = browser_service.read_cart_state

      # Click the ATC button
      click_result = browser_service.click_add_to_cart

      unless click_result[:clicked]
        return fail_result(
          message: "Add-to-Cart button could not be clicked",
          technical_details: {
            selector_used: structural["selector_used"],
            click_error: click_result[:error]
          },
          evidence: {
            button_found: true,
            button_visible: true,
            button_enabled: true,
            click_succeeded: false
          },
          suggestions: [
            "Check for JavaScript errors blocking form submission",
            "Verify the product form's action URL is correct"
          ]
        )
      end

      # Read cart state after ATC
      cart_after = browser_service.read_cart_state
      item_added = cart_after[:item_count] > cart_before[:item_count]

      # Cleanup: remove the item we added
      if item_added && cart_after[:items].present?
        added_item_key = cart_after[:items].last&.dig("key") || cart_after[:items].last&.dig(:key)
        browser_service.clear_cart_item(added_item_key) if added_item_key
      end

      record_validation(item_added)

      if item_added
        pass_result(
          message: "Add-to-Cart is fully functional — item successfully added to cart",
          technical_details: {
            selector_used: structural["selector_used"],
            button_text: structural["button_text"],
            cart_before_count: cart_before[:item_count],
            cart_after_count: cart_after[:item_count]
          },
          evidence: {
            button_found: true,
            button_visible: true,
            button_enabled: true,
            form_valid: true,
            item_added_to_cart: true,
            scan_depth: "deep"
          }
        )
      else
        fail_result(
          message: "Add-to-Cart button clicks but item is not added to the cart",
          confidence: 0.95,
          technical_details: {
            selector_used: structural["selector_used"],
            button_text: structural["button_text"],
            cart_before_count: cart_before[:item_count],
            cart_after_count: cart_after[:item_count],
            cart_error: cart_after[:error]
          },
          evidence: {
            button_found: true,
            button_visible: true,
            button_enabled: true,
            click_succeeded: true,
            item_added_to_cart: false,
            scan_depth: "deep"
          },
          suggestions: [
            "Check that the product has available inventory",
            "Verify the product form submits the correct variant ID",
            "Look for JavaScript errors in the browser console after clicking Add to Cart"
          ]
        )
      end
    end

    # Text patterns indicating sold-out (English-only is fine here since
    # Shopify themes use `product.available` logic, not just text)
    def sold_out_text?(text)
      return false if text.blank?
      normalized = text.to_s.downcase.strip
      normalized.include?("sold out") ||
        normalized.include?("unavailable") ||
        normalized.include?("out of stock") ||
        normalized.include?("notify me")
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

          return {
            button_found: true,
            button_visible: isVisible,
            button_enabled: !button.disabled && !button.hasAttribute('aria-disabled'),
            button_text: (button.textContent || button.value || '').trim().substring(0, 100),
            selector_used: selectorUsed,
            form_found: !!(form || parentForm),
            form_valid: formValid,
            form_action: formAction,
            has_click_handler: button.onclick !== null || button.hasAttribute('onclick') || formValid,
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
