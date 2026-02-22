# Common Issues and Fixes

When Prowl finds a problem on one of your product pages, it tells you what's wrong and how serious it is. This guide explains each issue type in detail and walks you through what you can do about it.

---

## Add to Cart Button Not Working

**Severity:** High

### What It Means

Prowl couldn't find a working "Add to Cart" button on your product page. This means customers visiting this page may not be able to add the product to their cart.

### Why It Matters

This is the most critical issue a product page can have. If customers can't add a product to their cart, you lose that sale entirely — and most customers will leave without telling you something was wrong.

### What You Can Do

1. **Visit the product page yourself** — Open the page in your browser and try clicking "Add to Cart." Check on both desktop and mobile.
2. **Check for recent theme changes** — If you recently updated your theme or customized your template, the button may have been accidentally removed or hidden.
3. **Review installed apps** — Some apps modify your product page and can interfere with the Add to Cart button. Try temporarily disabling recently installed apps to see if that resolves the issue.
4. **Check the product in Shopify admin** — Make sure the product is active, has at least one variant in stock, and isn't set to "Draft" status.
5. **Contact your theme developer** — If you can't identify the cause, reach out to the developer of your theme for help.

---

## Variant Selector Errors

**Severity:** High

### What It Means

Prowl detected errors related to the variant selector — the part of the page where customers choose options like size, color, or material.

### Why It Matters

If the variant selector isn't working, customers can't choose the specific version of the product they want. They may see the wrong price, select an unavailable option, or not be able to add the product to their cart at all.

### What You Can Do

1. **Test the variant selector yourself** — Visit the product page and try selecting every option combination. Look for any that don't work or show errors.
2. **Check for app conflicts** — Apps that modify swatches, color pickers, or variant selectors can sometimes conflict with each other or with your theme. Try disabling swatch or variant-related apps one at a time.
3. **Review your product options** — In Shopify admin, check that all variants are properly set up with valid option values and inventory.
4. **Check your theme's JavaScript** — If you've added custom code to your theme, it may be interfering with the default variant selector behavior. Revert recent changes to see if the issue clears.

---

## JavaScript Errors

**Severity:** High

### What It Means

Prowl found JavaScript errors occurring when your product page loads. JavaScript powers most of the interactive features on your page.

### Why It Matters

JavaScript errors can break things like image galleries, variant selectors, quantity pickers, reviews widgets, and more. Your page may look normal at first glance, but key features could silently be non-functional.

### What You Can Do

1. **Check for app conflicts** — The most common cause of JavaScript errors is a conflict between apps. If you recently installed or updated an app, try disabling it to see if the error goes away.
2. **Revert recent theme changes** — If you recently edited your theme code (especially `.liquid` or `.js` files), try reverting those changes.
3. **Test in a different browser** — Sometimes JavaScript errors are browser-specific. Test in Chrome, Safari, and Firefox to see if the issue is consistent.
4. **Check your browser's developer console** — Right-click on the page, select "Inspect," and go to the "Console" tab to see error details. Share these with your developer or theme support team.
5. **Contact support** — If you're using a third-party theme, reach out to the theme developer with the error details.

---

## Liquid Template Errors

**Severity:** Medium

### What It Means

Prowl found Liquid rendering errors in your page content. Liquid is the template language Shopify uses to build your store pages. When a Liquid error occurs, part of your page may display incorrectly or show error text.

### Why It Matters

Liquid errors can cause missing sections, broken layouts, or visible error messages on your page. While they may not completely prevent purchases, they make your store look unprofessional and can confuse customers.

### What You Can Do

1. **Look at the product page** — Check if you can see any visible error messages or missing content on the page.
2. **Check theme customizations** — If you've edited your theme's Liquid files, look for recent changes that may have introduced a syntax error.
3. **Review translation settings** — "Translation missing" errors usually mean your theme is trying to display a translation that doesn't exist. Check your theme language settings in **Online Store > Themes > Actions > Edit languages**.
4. **Update your theme** — If you're using an older version of your theme, updating to the latest version may fix known Liquid issues.
5. **Contact your theme developer** — Liquid errors in the base theme are the theme developer's responsibility. Report the issue to them with the product page URL.

---

## Product Images Not Loading

**Severity:** Medium

### What It Means

One or more product images failed to load when Prowl scanned the page. Customers visiting this page may see broken image placeholders instead of your product photos.

### Why It Matters

Product images are one of the biggest factors in a customer's decision to buy. Missing or broken images reduce trust and can significantly lower your conversion rate.

### What You Can Do

1. **Visit the product page** — Check if the images are loading for you. Try loading the page in an incognito/private window to rule out caching issues.
2. **Check the product in Shopify admin** — Go to the product editor and make sure all images are still attached. Re-upload any that appear broken.
3. **Check image file sizes** — Very large images may time out during loading. Shopify recommends keeping product images under 20 MB.
4. **Look for broken image URLs** — If you've moved or deleted images, existing references to them will break. Re-upload the images to refresh the URLs.
5. **Check your CDN or image apps** — If you use an app for image optimization or a custom CDN, it may be causing the issue. Try disabling it temporarily.

---

## Price Not Visible

**Severity:** High

### What It Means

Prowl couldn't find a visible product price on the page. Customers visiting this page may not see how much the product costs.

### Why It Matters

Price is essential information for any purchase decision. If customers can't see the price, most will leave the page rather than try to figure it out. This can also raise trust concerns.

### What You Can Do

1. **Check the product page yourself** — Visit the page and see if the price is visible. Check both desktop and mobile views.
2. **Verify the product has a price** — In Shopify admin, open the product and confirm all variants have a price set.
3. **Check your theme customization** — Some themes allow you to hide the price in theme settings. Check **Online Store > Themes > Customize** and look for price-related settings on the product page template.
4. **Review recent theme changes** — If you recently edited your theme code, you may have accidentally removed or broken the price display.
5. **Check for Liquid errors** — A Liquid error in the price section of your template could prevent the price from rendering. Look for related Liquid errors in your Prowl dashboard.

---

## Slow Page Load

**Severity:** Low

### What It Means

Your product page took more than 5 seconds to fully load. Prowl measures load time the same way a customer's browser would.

### Why It Matters

Slow pages frustrate customers. Studies consistently show that longer load times lead to higher bounce rates — customers leave before they even see your product. While this won't break your page, it can quietly reduce your sales over time.

### What You Can Do

1. **Optimize your images** — Large, uncompressed images are the most common cause of slow pages. Use Shopify's built-in image optimization or an image compression app.
2. **Review installed apps** — Each app can add scripts that slow down your page. Audit your apps and remove any you're not actively using.
3. **Reduce custom code** — If you've added custom JavaScript or CSS to your theme, check if any of it is slowing things down.
4. **Use a lightweight theme** — Some themes are more performance-optimized than others. If you're consistently seeing slow load times, consider switching to a faster theme.
5. **Check Shopify's speed report** — Shopify has a built-in speed report in **Online Store > Themes**. Compare it with what Prowl is showing you.

---

## Still Need Help?

If you've tried the steps above and the issue persists, here are your options:

- **Rescan the page** — After making changes, use the Rescan button in your Prowl dashboard to verify the fix.
- **Contact your theme developer** — For theme-related issues, they're your best resource.
- **Reach out to Shopify support** — For issues with products, settings, or your Shopify account.
- **Check our [Troubleshooting Guide](troubleshooting.md)** — For problems with Prowl itself.
