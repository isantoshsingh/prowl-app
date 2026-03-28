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
      ".product-form__submit",
      ".product-form__cart-submit",
      "#AddToCart",
      "#add-to-cart",
      "[data-add-to-cart]",
      "button.add-to-cart",
      ".add-to-cart-button",
      'input[type="submit"][name="add"]'
    ].freeze

    PRODUCT_FORM_SELECTORS = [
      'product-form form[action*="/cart/add"]',
      'form[action*="/cart/add"]',
      "form.product-form",
      "form[data-product-form]",
      "form.shopify-product-form",
      "#product-form",
      "#AddToCartForm"
    ].freeze

    def initialize(browser_service, scan_depth: :quick, shop: nil, product_id: nil, pdp_price_result: nil)
      super(browser_service)
      @scan_depth = scan_depth
      @shop = shop
      @product_id = product_id
      @pdp_price_result = pdp_price_result
      @journey_results = []
    end

    def check_name
      "add_to_cart"
    end

    # Returns journey-stage detection results (cart verification, feedback, price mismatch, checkout)
    # These are separate from the primary ATC detection result.
    def all_results
      @journey_results
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
      if button_found && !button_enabled && sold_out_text?(structural["button_text"], structural)
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
          confidence: [ calculated_confidence, 0.85 ].max,
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
        confidence: [ calculated_confidence, 0.85 ].max,
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
    # Clicks ATC, verifies cart updates, then runs extended journey checks for Monitor tier.
    # Uses ensure block to guarantee cart cleanup even on failures.
    def run_funnel_test(structural)
      added_item_key = nil

      begin
        # Read cart state before ATC
        cart_before = browser_service.read_cart_state
        initial_cart_count = cart_before[:item_count]

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

        # Poll cart state — some themes have async delay between ATC click and cart update.
        cart_after = nil
        item_added = false
        max_poll_attempts = 4

        max_poll_attempts.times do |attempt|
          cart_after = browser_service.read_cart_state
          item_added = cart_after[:item_count] > initial_cart_count
          break if item_added
          break if attempt == max_poll_attempts - 1
          sleep(1.0)
        end

        # Track the added item key for cleanup
        if item_added && cart_after[:items].present?
          added_item_key = cart_after[:items].last&.dig("key") || cart_after[:items].last&.dig(:key)
        end

        record_validation(item_added)

        unless item_added
          return fail_result(
            message: "Add-to-Cart button clicks but item is not added to the cart",
            confidence: 0.95,
            technical_details: {
              selector_used: structural["selector_used"],
              button_text: structural["button_text"],
              cart_before_count: initial_cart_count,
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

        # ── ATC passed — now run extended journey checks if Monitor tier ──
        journey_stages = resolve_journey_stages
        if journey_stages.include?(:cart)
          run_cart_journey_checks(structural, cart_after, added_item_key)
        end

        if journey_stages.include?(:checkout_handoff)
          run_checkout_handoff(added_item_key)
        end

        # Return the primary ATC result (pass). Journey issues are appended
        # as separate detection results via @journey_results.
        pass_result(
          message: "Add-to-Cart is fully functional — item successfully added to cart",
          technical_details: {
            selector_used: structural["selector_used"],
            button_text: structural["button_text"],
            cart_before_count: initial_cart_count,
            cart_after_count: cart_after[:item_count]
          },
          evidence: {
            button_found: true,
            button_visible: true,
            button_enabled: true,
            form_valid: true,
            item_added_to_cart: true,
            scan_depth: "deep",
            journey_stages: journey_stages.map(&:to_s)
          }
        )
      ensure
        # Always clean up the test item from cart
        cleanup_cart_item(added_item_key)
      end
    end

    # ── Extended journey checks (Monitor tier only) ──────────────────────

    # Runs cart-stage checks: item verification, feedback detection, price mismatch
    def run_cart_journey_checks(structural, cart_after, added_item_key)
      # 1. Cart item verification
      if @product_id
        verify_result = browser_service.verify_cart_item(@product_id)
        unless verify_result[:verified]
          @journey_results << build_result(
            status: "fail",
            message: "Cart item verification failed: #{verify_result[:reason]}",
            confidence: 0.95,
            technical_details: {
              expected_product_id: @product_id.to_s,
              actual_product_id: verify_result[:actual_product_id],
              reason: verify_result[:reason]
            },
            evidence: {
              reason: verify_result[:reason],
              expected_product_id: @product_id.to_s,
              actual_cart_state: verify_result[:cart_state]
            },
            suggestions: [
              "Verify the product form submits the correct product/variant ID",
              "Check if a third-party app is modifying cart contents"
            ]
          ).merge(check: "atc_funnel")
          return # Skip further cart checks if item verification failed
        end

        # 2. Price mismatch detection
        check_price_mismatch(verify_result[:cart_price_cents])
      end

      # 3. Cart feedback detection
      feedback = browser_service.cart_feedback_visible?
      unless feedback[:visible]
        @journey_results << build_result(
          status: "warning",
          message: "No visible cart feedback after adding item — customers may not realize the item was added",
          confidence: 0.85,
          technical_details: { feedback_type: feedback[:feedback_type] },
          evidence: {
            cart_item_verified: true,
            feedback_visible: false,
            feedback_type: feedback[:feedback_type]
          },
          suggestions: [
            "Consider adding a cart drawer or notification after Add to Cart",
            "This may be an intentional theme design choice"
          ]
        ).merge(check: "cart_feedback")
      else
        Rails.logger.info("[AddToCartDetector] Cart feedback detected: #{feedback[:feedback_type]}")
      end
    rescue StandardError => e
      Rails.logger.error("[AddToCartDetector] Cart journey checks failed: #{e.message}")
    end

    # Compares PDP price with cart price
    def check_price_mismatch(cart_price_cents)
      return unless @pdp_price_result && cart_price_cents

      pdp_price_text = @pdp_price_result.dig(:details, :evidence, :price_text) ||
                       @pdp_price_result.dig(:details, :technical_details, :price_text)
      return if pdp_price_text.blank?

      pdp_cents = parse_price_to_cents(pdp_price_text)
      return unless pdp_cents && pdp_cents > 0

      difference_percent = ((pdp_cents - cart_price_cents).abs.to_f / pdp_cents * 100).round(2)

      if difference_percent > 1.0
        @journey_results << build_result(
          status: "fail",
          message: "Price mismatch: PDP shows #{pdp_price_text} but cart has #{format_cents(cart_price_cents)}",
          confidence: 0.9,
          technical_details: {
            pdp_price_text: pdp_price_text,
            pdp_price_cents: pdp_cents,
            cart_price_cents: cart_price_cents,
            difference_percent: difference_percent
          },
          evidence: {
            pdp_price: pdp_price_text,
            cart_price: format_cents(cart_price_cents),
            difference_percent: difference_percent
          },
          suggestions: [
            "Check if a discount or app is modifying the cart price",
            "Verify the displayed price matches the Shopify admin price"
          ]
        ).merge(check: "price_mismatch")
      end
    rescue StandardError => e
      Rails.logger.warn("[AddToCartDetector] Price mismatch check failed: #{e.message}")
    end

    # Navigates to checkout and verifies the handoff works
    def run_checkout_handoff(added_item_key)
      checkout_result = browser_service.navigate_to_checkout
      url = checkout_result[:url].to_s

      is_valid_checkout = url.include?("checkout.shopify.com") ||
                          url.include?("shop.app") ||
                          url.include?("/checkouts/")

      if checkout_result[:error].present? && !is_valid_checkout
        @journey_results << build_result(
          status: "fail",
          message: "Checkout page failed to load",
          confidence: 0.9,
          technical_details: {
            redirect_url: url,
            error: checkout_result[:error]
          },
          evidence: {
            redirect_url: url,
            error_message: checkout_result[:error]
          },
          suggestions: [
            "Verify your checkout settings in Shopify admin",
            "Check if a third-party app is interfering with checkout"
          ]
        ).merge(check: "checkout")
      elsif !is_valid_checkout
        @journey_results << build_result(
          status: "fail",
          message: "Checkout did not redirect to Shopify checkout",
          confidence: 0.85,
          technical_details: {
            redirect_url: url,
            is_shopify_checkout: false
          },
          evidence: {
            redirect_url: url,
            status_code: checkout_result[:status_code]
          },
          suggestions: [
            "Verify checkout is not password-protected or restricted",
            "Check that the store's checkout URL is configured correctly"
          ]
        ).merge(check: "checkout")
      else
        Rails.logger.info("[AddToCartDetector] Checkout handoff verified: #{url}")
      end
    rescue StandardError => e
      Rails.logger.error("[AddToCartDetector] Checkout handoff check failed: #{e.message}")
    end

    # ── Helpers ──────────────────────────────────────────────────────────

    def resolve_journey_stages
      return [ :pdp ] unless @shop
      plan = BillingPlanService.plan_for(@shop)
      plan[:journey_stages] || [ :pdp ]
    rescue StandardError
      [ :pdp ]
    end

    def cleanup_cart_item(item_key)
      return unless item_key
      browser_service.clear_cart_item(item_key)
    rescue StandardError => e
      Rails.logger.warn("[AddToCartDetector] Cart cleanup failed: #{e.message}")
    end

    def parse_price_to_cents(price_text)
      return nil if price_text.blank?
      # Strip currency symbols and whitespace, handle comma as thousands separator
      cleaned = price_text.to_s.gsub(/[^\d.,]/, "")
      # Handle formats like "1,299.99" or "29.99"
      if cleaned.include?(",") && cleaned.include?(".")
        cleaned = cleaned.gsub(",", "")
      elsif cleaned.include?(",") && cleaned.split(",").last.length == 2
        # European format: "29,99" → "29.99"
        cleaned = cleaned.gsub(",", ".")
      elsif cleaned.include?(",")
        # Thousands separator only: "1,299" → "1299"
        cleaned = cleaned.gsub(",", "")
      end
      (cleaned.to_f * 100).round
    rescue StandardError
      nil
    end

    def format_cents(cents)
      "$#{'%.2f' % (cents / 100.0)}"
    end

    # Checks if a product appears sold out using multiple signals:
    #   1. Button text (English patterns)
    #   2. Structural data from the DOM (language-independent)
    def sold_out_text?(text, structural = nil)
      # Check DOM-level sold-out signal (language-independent)
      if structural
        return true if structural["product_unavailable"]
      end

      # Check button text patterns
      return false if text.blank?
      normalized = text.to_s.downcase.strip
      normalized.include?("sold out") ||
        normalized.include?("unavailable") ||
        normalized.include?("out of stock") ||
        normalized.include?("notify me") ||
        normalized.include?("epuise") ||       # French
        normalized.include?("agotado") ||      # Spanish
        normalized.include?("ausverkauft")     # German
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

          // Language-independent sold-out detection via Shopify product JSON
          // Shopify exposes product.available in the product JSON (set by Liquid)
          let productUnavailable = false;
          try {
            const productJson = document.querySelector('[data-product-json], script[type="application/json"][data-product-json], #ProductJson-product-template');
            if (productJson) {
              const product = JSON.parse(productJson.textContent);
              productUnavailable = product.available === false;
            }
          } catch(e) { /* ignore parse errors */ }

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
            product_unavailable: productUnavailable,
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
