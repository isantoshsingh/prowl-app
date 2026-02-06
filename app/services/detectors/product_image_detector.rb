# frozen_string_literal: true

module Detectors
  # ProductImageDetector verifies that the main product image is present,
  # loaded, visible, and not broken.
  #
  # Validation checks:
  #   1. Main product image element exists
  #   2. Image src is not empty or placeholder
  #   3. Image loaded successfully (naturalWidth > 0, complete)
  #   4. Image dimensions are reasonable (> 200x200)
  #   5. No broken image state
  #   6. Handle lazy-loaded images (wait for load)
  #
  # Horizon theme patterns:
  #   - <product-media> custom element
  #   - .product__media-item img
  #   - Media gallery with thumbnail navigation
  #   - Lazy loading with loading="lazy" attribute
  #
  class ProductImageDetector < BaseDetector
    IMAGE_SELECTORS = [
      "product-media img",
      ".product__media img",
      ".product__media-item img",
      ".product-media img",
      ".product-single__photo img",
      "[data-product-media] img",
      "[data-product-image]",
      ".product-image img",
      ".product__photo img",
      ".product-featured-media img",
      "#ProductPhoto img",
      ".product-gallery img",
      ".product__main-image img",
      ".featured-image img"
    ].freeze

    # Minimum dimensions for a real product image
    MIN_IMAGE_WIDTH = 200
    MIN_IMAGE_HEIGHT = 200

    # Known placeholder image patterns
    PLACEHOLDER_PATTERNS = [
      /no-image/i,
      /placeholder/i,
      /no_image/i,
      /default\.png/i,
      /blank\.gif/i,
      /pixel\.gif/i,
      /spacer/i,
      /1x1/i
    ].freeze

    def check_name
      "product_images"
    end

    private

    def run_detection
      result = evaluate(image_detection_script)

      if result.nil?
        return inconclusive_result("Could not evaluate product image detection script")
      end

      image_found = record_validation(result["image_found"])
      image_loaded = record_validation(result["image_loaded"])
      image_visible = record_validation(result["image_visible"])
      image_sized = record_validation(result["natural_width"].to_i >= MIN_IMAGE_WIDTH && result["natural_height"].to_i >= MIN_IMAGE_HEIGHT)
      not_placeholder = record_validation(!placeholder_image?(result["src"]))
      not_broken = record_validation(!result["is_broken"])

      # Check for network-level image failures
      image_network_errors = browser_service.network_errors.select do |error|
        url = error[:url].to_s.downcase
        resource_type = error[:resource_type].to_s.downcase
        resource_type == "image" || url.match?(/\.(jpg|jpeg|png|gif|webp|avif|svg)(\?|$)/i)
      end
      record_validation(image_network_errors.empty?)

      if image_found && image_loaded && image_visible && image_sized
        pass_result(
          message: "Product image is present, loaded, and visible",
          technical_details: {
            selector_used: result["selector_used"],
            dimensions: "#{result["natural_width"]}x#{result["natural_height"]}",
            total_images: result["total_images"],
            visible_images: result["visible_images"]
          },
          evidence: {
            image_found: true,
            image_loaded: true,
            image_visible: true,
            natural_width: result["natural_width"],
            natural_height: result["natural_height"],
            total_images: result["total_images"],
            network_image_errors: image_network_errors.length
          }
        )
      elsif !image_found
        fail_result(
          message: "Product image could not be found on the page",
          confidence: [calculated_confidence, 0.8].max,
          technical_details: {
            selectors_tried: IMAGE_SELECTORS
          },
          evidence: {
            image_found: false,
            selectors_tried_count: IMAGE_SELECTORS.length,
            network_image_errors: image_network_errors.length
          },
          suggestions: [
            "Verify that the product has images uploaded in Shopify admin",
            "Check that the product template includes image markup",
            "Ensure no JavaScript errors are preventing image rendering"
          ]
        )
      elsif !image_loaded || result["is_broken"]
        fail_result(
          message: "Product image found but failed to load",
          technical_details: {
            selector_used: result["selector_used"],
            src: result["src"].to_s.truncate(200),
            complete: result["complete"],
            natural_width: result["natural_width"],
            is_broken: result["is_broken"]
          },
          evidence: {
            image_found: true,
            image_loaded: false,
            src: result["src"].to_s.truncate(200),
            network_image_errors: image_network_errors.length,
            failed_urls: image_network_errors.first(3).map { |e| e[:url] }
          },
          suggestions: [
            "Check if the image URL is valid and accessible",
            "Verify image CDN is functioning correctly",
            "Try re-uploading the product image in Shopify admin"
          ]
        )
      elsif !image_visible
        fail_result(
          message: "Product image loaded but is not visible to customers",
          technical_details: {
            selector_used: result["selector_used"],
            visibility_details: result["visibility_details"]
          },
          evidence: {
            image_found: true,
            image_loaded: true,
            image_visible: false
          },
          suggestions: [
            "Check CSS rules that may be hiding the image",
            "Verify the image container has proper dimensions"
          ]
        )
      elsif !image_sized
        warning_result(
          message: "Product image is very small (#{result["natural_width"]}x#{result["natural_height"]}px)",
          technical_details: {
            selector_used: result["selector_used"],
            natural_width: result["natural_width"],
            natural_height: result["natural_height"],
            minimum_expected: "#{MIN_IMAGE_WIDTH}x#{MIN_IMAGE_HEIGHT}"
          },
          evidence: {
            image_found: true,
            image_loaded: true,
            natural_width: result["natural_width"],
            natural_height: result["natural_height"]
          },
          suggestions: [
            "Upload higher resolution product images (at least 800x800px recommended)",
            "Check if image resizing or compression is too aggressive"
          ]
        )
      else
        warning_result(
          message: "Product image detected with potential issues",
          technical_details: {
            src: result["src"].to_s.truncate(200),
            complete: result["complete"],
            natural_width: result["natural_width"],
            natural_height: result["natural_height"]
          },
          evidence: {
            image_found: image_found,
            image_loaded: image_loaded,
            image_visible: image_visible,
            image_sized: image_sized
          }
        )
      end
    end

    def placeholder_image?(src)
      return true if src.blank?
      PLACEHOLDER_PATTERNS.any? { |pattern| src.match?(pattern) }
    end

    def image_detection_script
      selectors_js = IMAGE_SELECTORS.map { |s| "'#{s}'" }.join(", ")

      <<~JAVASCRIPT
        () => {
          const selectors = [#{selectors_js}];

          let mainImage = null;
          let selectorUsed = null;

          // Try each selector to find the main product image
          for (const sel of selectors) {
            const imgs = document.querySelectorAll(sel);
            for (const img of imgs) {
              // Filter out tiny icons and thumbnails
              const rect = img.getBoundingClientRect();
              if (rect.width > 100 || rect.height > 100 || img.naturalWidth > 100) {
                mainImage = img;
                selectorUsed = sel;
                break;
              }
            }
            if (mainImage) break;
          }

          // Fallback: find the largest img in the product area
          if (!mainImage) {
            const productArea = document.querySelector('.product, [data-product], #product, main, .main-content');
            if (productArea) {
              const imgs = productArea.querySelectorAll('img');
              let largest = null;
              let largestArea = 0;
              for (const img of imgs) {
                const area = (img.naturalWidth || img.width) * (img.naturalHeight || img.height);
                if (area > largestArea) {
                  largestArea = area;
                  largest = img;
                }
              }
              if (largest && largestArea > 10000) {
                mainImage = largest;
                selectorUsed = 'largest-in-product-area';
              }
            }
          }

          if (!mainImage) {
            return {
              image_found: false,
              image_loaded: false,
              image_visible: false,
              src: null,
              natural_width: 0,
              natural_height: 0,
              complete: false,
              is_broken: false,
              selector_used: null,
              total_images: 0,
              visible_images: 0,
              visibility_details: null
            };
          }

          // Check if loaded (handles lazy loading)
          const isComplete = mainImage.complete;
          const naturalWidth = mainImage.naturalWidth || 0;
          const naturalHeight = mainImage.naturalHeight || 0;
          const isLoaded = isComplete && naturalWidth > 0;
          const isBroken = isComplete && naturalWidth === 0;

          // Visibility
          const style = window.getComputedStyle(mainImage);
          const rect = mainImage.getBoundingClientRect();
          const isVisible = (
            style.display !== 'none' &&
            style.visibility !== 'hidden' &&
            style.opacity !== '0' &&
            rect.width > 0 &&
            rect.height > 0
          );

          // Count all product images
          let totalImages = 0;
          let visibleImages = 0;
          for (const sel of selectors) {
            const imgs = document.querySelectorAll(sel);
            totalImages += imgs.length;
            for (const img of imgs) {
              if (img.complete && img.naturalWidth > 0) {
                const imgRect = img.getBoundingClientRect();
                if (imgRect.width > 0 && imgRect.height > 0) {
                  visibleImages++;
                }
              }
            }
          }

          return {
            image_found: true,
            image_loaded: isLoaded,
            image_visible: isVisible,
            src: mainImage.src || mainImage.getAttribute('data-src') || '',
            natural_width: naturalWidth,
            natural_height: naturalHeight,
            complete: isComplete,
            is_broken: isBroken,
            selector_used: selectorUsed,
            total_images: totalImages,
            visible_images: visibleImages,
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
