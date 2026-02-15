---
description: Shopify Polaris Web Components design guide for "Built for Shopify" embedded apps using App Home
---

# Shopify Polaris Web Components — Design Skill

This skill documents the **correct** usage of Polaris Web Components for Shopify embedded apps (App Home). These are NOT the React Polaris components — many attributes differ.

> ⚠️ **CRITICAL: Never use self-closing tags (`<s-component />`) with web components!** HTML custom elements do NOT support self-closing syntax. The browser treats `/>` as a stray `/` attribute and keeps the tag open, swallowing all following siblings as children. Always use explicit closing tags: `<s-component></s-component>`.

**Official Docs:**
- Visual Design: https://shopify.dev/docs/apps/design/visual-design
- Polaris Web Components: https://shopify.dev/docs/api/app-home/polaris-web-components
- Patterns & Compositions: https://shopify.dev/docs/api/app-home/patterns
- Using Components: https://shopify.dev/docs/api/app-home/using-polaris-components
- ClickableChip: https://shopify.dev/docs/api/app-home/polaris-web-components/actions/clickablechip

---

## 1. "Built for Shopify" Core Requirements

- **Use App Bridge and Polaris Web Components exclusively** — mimic Shopify admin look-and-feel
- **Mobile-friendly** interface
- **Integrated navigation** via `s-app-nav`
- **Contextual Save Bar** for all forms (via App Bridge, `data-save-bar`)
- **Homepage** must clearly indicate setup status, show performance metrics, and provide daily value
- **No custom CSS for layout** — use Polaris components for spacing and structure
- **No external UI frameworks** (no Tailwind, Bootstrap, etc.)
- **Headings in sentence case** — use sentence case for all headings (e.g. `s-page` heading, `s-section` heading, `s-heading`). Only the first word and proper nouns are capitalized (e.g. "Scan history", "Alert preferences", not "Scan History", "Alert Preferences").

---

## 2. Available Components

### Layout & Structure
| Component | Purpose | Key Properties |
|---|---|---|
| `s-page` | Page wrapper with heading, breadcrumbs, actions | `heading`, `inlineSize="base"` (enables sidebar), slots: `primary-action`, `breadcrumb-actions`, `accessory`, `aside` |
| `s-section` | Card-like container | `heading`, `accessibilityLabel`. **Do not set `padding="none"`** — use default padding. |
| `s-box` | Generic container for spacing & sizing | `padding`, `paddingBlock`, `paddingBlockStart`, `paddingInline`, `border`, `borderRadius`, `background`, `maxInlineSize`, `maxBlockSize` |
| `s-stack` | Flexbox layout | `direction` ("inline" or "block"), `gap`, `align`, `justify` |
| `s-grid` | CSS Grid layout | `gridTemplateColumns`, `gap`, `justifyItems`, `alignItems`, `paddingBlock`, `maxInlineSize` |
| `s-divider` | Visual separator line | `color`, `direction` |

### Actions
| Component | Purpose | Key Properties |
|---|---|---|
| `s-button` | Primary action element | `variant` ("primary", "secondary", "tertiary"), `tone` ("critical"), `href`, `fullWidth`, `disabled`, `icon` |
| `s-button-group` | Groups buttons together | Expects direct `s-button` children. **Do NOT nest `<form>` inside it** — use hidden forms + `onclick` instead |
| `s-link` | Navigation link | `href`, slots in `s-page` |
| `s-clickable-chip` | Filter/tag chip (clickable or link) | `color` ("subdued", "base", "strong"), `href`, `accessibilityLabel`, `removable`, slot `graphic` for icon. **Use inside `s-stack direction="inline" gap="base"`** so chips have visible spacing (see Filter chips pattern). |

### Feedback & Status
| Component | Purpose | Key Properties |
|---|---|---|
| `s-banner` | Alert/info banner | `tone` ("info", "success", "warning", "critical") |
| `s-badge` | Status indicator | `tone` ("info", "success", "attention", "warning", "critical") |
| `s-spinner` | Loading indicator | `size` ("small", "large") |

### Typography & Content
| Component | Purpose | Key Properties |
|---|---|---|
| `s-heading` | Section headings | Direct text content. **Use sentence case** for all heading text. |
| `s-paragraph` | Body text | Direct text content |
| `<strong>` | Bold text within paragraphs | Standard HTML |

### Media & Visuals
| Component | Purpose | Key Properties |
|---|---|---|
| `s-icon` | Icons | `type` (icon name), `tone` ("success", "critical", "caution", "subdued", "info") |
| `s-thumbnail` | Small product/media preview | `src`, `alt`, `size` ("small", "base", "large") |
| `s-image` | Full images | `src`, `alt`, `aspectRatio`, `inlineSize`, `blockSize` |
| `s-avatar` | User/entity avatar | `src`, `name`, `shape` ("circle", "square"), `size` |

### Form Components
| Component | Purpose | Key Properties |
|---|---|---|
| `s-text-field` | Text input | `label`, `name`, `value`, `placeholder`, `details` |
| `s-email-field` | Email input | `label`, `name`, `value`, `placeholder`, `details` |
| `s-select` | Dropdown select | `label`, `name`, `value`, `details`. Children: `<s-option value="...">` |
| `s-checkbox` | Checkbox | `label`, `name`, `value`, `checked`, `details` |
| `s-number-field` | Number input | `label`, `name`, `value`, `min`, `max`, `step` |

---

## 3. Components That Do NOT Exist in Web Components

These are React-only and will NOT work:
- ❌ `s-layout` / `s-layout-section`
- ❌ `s-card` (use `s-section` instead)
- ❌ `s-text` with `variant`, `fontWeight`, `tone` attributes (use `s-heading`, `s-paragraph`, `<strong>`)
- ❌ `s-inline-stack` / `s-block-stack` (use `s-stack` with `direction`)
- ❌ `s-resource-list` / `s-resource-item` (use composition pattern)
- ❌ `s-index-table` (use composition pattern)

---

## 4. Common Attribute Mistakes

### s-stack gap values
**Wrong (React tokens):** `gap="200"`, `gap="400"`, `gap="4"`
**Correct (Web Component tokens):** `gap="none"`, `gap="extra-tight"`, `gap="tight"`, `gap="base"`, `gap="loose"`

Additional gap tokens available: `"small-300"`, `"large-400"` (sizing tokens)

### s-grid
**Wrong:** `columns={3}`, `columns="3"`
**Correct:** `gridTemplateColumns="repeat(3, 1fr)"` or `gridTemplateColumns="1fr auto"`

### s-box background
**Wrong:** `background="bg-surface-secondary"`, `background="#f6f6f7"`
**Correct:** `background="subdued"`

### s-box border/borderRadius
**Wrong:** `border="1"`, `borderRadius="200"`
**Correct:** `border="base"`, `borderRadius="base"`

### s-section padding
**Do not use `padding="none"`** on `s-section`. Use the default padding (omit the attribute) so sections keep consistent card-like spacing.

### s-clickable-chip spacing
**Wrong:** Wrapping multiple `s-clickable-chip` in `s-stack direction="inline" gap="tight"` — chips render with no visible gap and text runs together (e.g. "OpenAcknowledgedResolved").
**Correct:** Use `s-stack direction="inline" gap="base"` when laying out filter chips. See [ClickableChip](https://shopify.dev/docs/api/app-home/polaris-web-components/actions/clickablechip) "Multiple Chips with Proper Spacing" example.

### List rows: badge/action on the right
**Wrong:** Using `s-stack direction="inline" justify="space-between"` to put a badge or action on the right — alignment can be inconsistent across browsers or when content wraps.
**Correct:** Use `s-grid gridTemplateColumns="1fr auto" gap="base" alignItems="center"` so the first column takes remaining space and the second column (badge or link) stays right-aligned. Same pattern as the Resource List example below.

### Meta lines (multiple facts in one line)
**Wrong:** Building a line from several adjacent `s-paragraph` or inline-stack children (e.g. "Scan #18" + "February 15..." + "8.4s load time"). They often render with no space and concatenate (e.g. "Scan #18February 15...").
**Correct:** Use a **single** `s-paragraph` and build the line in Ruby with explicit separators, e.g. `parts = ["Scan \##{id}", date_str]; parts << "#{load_s}s load time" if load_s; parts.join(' · ')`. Output that string once so spacing is guaranteed.

### Highlighting one value in a paragraph
To emphasize a key metric (e.g. load time) inside body text: wrap only that value in `<strong>`. Build the segment as HTML (e.g. `"#{value}s load time".sub(/\d+\.?\d*s/) { |m| "<strong>#{m}</strong>" }.html_safe`) and use `safe_join(parts, ' · '.html_safe)` for the full line so the rest stays escaped.

---

## 5. Layout Patterns

### Page with Sidebar
```html
<s-page heading="Dashboard" inlineSize="base">
  <s-button slot="primary-action" variant="primary" href="/add">Add</s-button>
  <s-link slot="breadcrumb-actions" href="/">Home</s-link>
  <s-badge slot="accessory" tone="info">5 items</s-badge>

  <!-- Main content goes here as direct children -->

  <div slot="aside">
    <s-section heading="Quick Actions">
      <!-- Sidebar content -->
    </s-section>
  </div>
</s-page>
```

### Empty State (Official Pattern)
```html
<s-section accessibilityLabel="Empty state section">
  <s-grid gap="base" justifyItems="center" paddingBlock="large-400">
    <s-box maxInlineSize="200px" maxBlockSize="200px">
      <s-image
        aspectRatio="1/0.5"
        src="https://cdn.shopify.com/static/images/polaris/patterns/callout.png"
        alt="Description"
      />
    </s-box>
    <s-grid justifyItems="center" maxInlineSize="450px" gap="base">
      <s-stack align="center">
        <s-heading>Title goes here</s-heading>
        <s-paragraph>Description text goes here.</s-paragraph>
      </s-stack>
      <s-button variant="primary">Primary Action</s-button>
    </s-grid>
  </s-grid>
</s-section>
```

### Resource List with Thumbnails
Use `s-grid gridTemplateColumns="1fr auto"` for each row so the **badge or actions stay right-aligned**; avoid `s-stack justify="space-between"` for that.
```html
<s-section heading="List title">
  <s-stack gap="none">
    <!-- Repeatable row -->
    <s-box border="base" padding="base">
      <s-grid gridTemplateColumns="1fr auto" gap="base" alignItems="center">
        <!-- Left: Thumbnail + Info -->
        <s-stack direction="inline" gap="base" align="center">
          <s-thumbnail src="IMAGE_URL" alt="Product" size="small" />
          <s-stack direction="block" gap="extra-tight">
            <strong>Product Title</strong>
            <s-stack direction="inline" gap="tight" align="center">
              <s-badge tone="success">Status</s-badge>
              <s-paragraph>Meta info here</s-paragraph>
            </s-stack>
          </s-stack>
        </s-stack>

        <!-- Right: Actions -->
        <s-stack direction="inline" gap="tight">
          <s-button>View</s-button>
          <s-button>Edit</s-button>
          <s-button tone="critical">Delete</s-button>
        </s-stack>
      </s-grid>
    </s-box>
  </s-stack>
</s-section>
```

### Subscription / Stats Grid
```html
<s-section heading="Subscription">
  <s-grid gridTemplateColumns="repeat(4, 1fr)" gap="base">
    <s-stack direction="block" gap="extra-tight">
      <s-paragraph>Label</s-paragraph>
      <strong>Value</strong>
    </s-stack>
    <!-- repeat for each stat -->
  </s-grid>
</s-section>
```

### Feature List with Check Icons
```html
<s-section heading="What's Included">
  <s-stack direction="block" gap="base">
    <s-stack direction="inline" gap="tight" align="start">
      <s-icon type="check-circle-filled" tone="success"></s-icon>
      <s-stack direction="block" gap="extra-tight">
        <s-paragraph><strong>Feature title</strong></s-paragraph>
        <s-paragraph>Feature description</s-paragraph>
      </s-stack>
    </s-stack>
    <!-- repeat for each feature -->
  </s-stack>
</s-section>
```

### Filter Chips (ClickableChip)
Use `s-clickable-chip` for status/category filters (e.g. All, Open, Resolved). **Must use `gap="base"`** on the wrapping stack so chips do not run together. Use `color="base"` for the active filter, `color="subdued"` for inactive. Reference: [ClickableChip](https://shopify.dev/docs/api/app-home/polaris-web-components/actions/clickablechip).
```html
<s-section heading="Filter by status">
  <s-stack direction="inline" gap="base">
    <s-clickable-chip color="base" href="/issues" accessibilityLabel="Filter by all">All</s-clickable-chip>
    <s-clickable-chip color="subdued" href="/issues?status=open" accessibilityLabel="Filter by open">Open</s-clickable-chip>
    <s-clickable-chip color="subdued" href="/issues?status=resolved" accessibilityLabel="Filter by resolved">Resolved</s-clickable-chip>
  </s-stack>
</s-section>
```

---

## 6. Spacing Between Sections

`s-section` has NO external margin. To add gaps between sections:

**Use `s-box` with `paddingBlockStart`:**
```html
<s-section heading="First Section">...</s-section>

<s-box paddingBlockStart="small">
  <s-section heading="Second Section">...</s-section>
</s-box>
```

Available `paddingBlockStart` values: `"none"`, `"extra-tight"`, `"tight"`, `"base"`, `"loose"`, `"small"`, `"small-300"`, `"large-400"`

> **Note:** Wrapping sections in `s-stack` with `gap` may not work for top-level sections. Use `s-box paddingBlockStart` instead.

---

## 7. s-button-group Gotcha

`s-button-group` expects **direct `s-button` children only**. Nesting `<form>` elements inside breaks the layout.

**Wrong:**
```html
<s-button-group>
  <form method="post"><s-button type="submit">Save</s-button></form>
</s-button-group>
```

**Correct:**
```html
<s-stack direction="inline" gap="tight">
  <s-button onclick="document.getElementById('my-form').submit()">Save</s-button>
</s-stack>
<form id="my-form" action="/save" method="post" style="display: none;">
  <input type="hidden" name="authenticity_token" value="...">
</form>
```

---

## 8. App Bridge Integration

### Resource Picker
```javascript
const selected = await shopify.resourcePicker({
  type: 'product',
  action: 'select',
  multiple: 5,  // or false for single
  filter: {
    draft: false,
    archived: false,
    variants: false
  }
});

// Extract data from response
selected.forEach(product => {
  product.id;        // "gid://shopify/Product/12345"
  product.title;     // "Product Title"
  product.handle;    // "product-handle"
  product.images[0].originalSrc;  // Image URL
});
```

### Toast Notifications
```javascript
shopify.toast.show('Message', { duration: 3000 });
shopify.toast.show('Error message', { duration: 3000, isError: true });
```

### Session Token
```javascript
const token = await shopify.idToken();
// Use in headers: { 'Authorization': `Bearer ${token}` }
```

### Contextual Save Bar
Add `data-save-bar` attribute to `<form>` elements. App Bridge auto-detects changes and shows the save bar.

---

## 9. Common Icon Names

Status icons: `check-circle`, `check-circle-filled`, `alert-circle`, `alert-triangle`, `clock`, `info`
Action icons: `product`, `refresh`, `delete`, `view`, `edit`, `search`
Navigation icons: `arrow-left`, `arrow-right`, `chevron-down`, `chevron-up`, `external`

---

## 10. Embedded App Layout Setup

The layout file must include Polaris and App Bridge scripts:
```html
<script src="https://cdn.shopify.com/shopifycloud/polaris.js"></script>
<script src="https://cdn.shopify.com/shopifycloud/app-bridge.js"></script>
```

Navigation is defined via `s-app-nav`:
```html
<s-app-nav>
  <s-link href="/home" label="Dashboard"></s-link>
  <s-link href="/product_pages" label="Monitored Pages"></s-link>
  <s-link href="/settings" label="Settings"></s-link>
  <s-link href="/billing" label="Pricing"></s-link>
</s-app-nav>
```
