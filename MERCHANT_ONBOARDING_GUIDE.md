# Merchant Onboarding Guide
## PDP Diagnostics - Silent Profit

This guide outlines the merchant onboarding experience for the PDP Diagnostics app, following Shopify's best practices for app design and user experience.

---

## Table of Contents

1. [Onboarding Philosophy](#onboarding-philosophy)
2. [Onboarding Flow Overview](#onboarding-flow-overview)
3. [Step-by-Step Merchant Journey](#step-by-step-merchant-journey)
4. [Homepage Template](#homepage-template)
5. [Setup Guide Component](#setup-guide-component)
6. [UI/UX Implementation Details](#uiux-implementation-details)
7. [Best Practices](#best-practices)

---

## Onboarding Philosophy

### Goals
- **Get merchants to value quickly** - First scan completed within 5 minutes
- **Progressive disclosure** - Don't overwhelm with all features at once
- **Clear success metrics** - Show immediate value from monitoring
- **Minimal friction** - Reduce steps between install and first value

### Key Principles
1. **Show, don't tell** - Demonstrate value with real data
2. **Guide, don't block** - Allow exploration while suggesting next steps
3. **Celebrate progress** - Acknowledge completion of setup steps
4. **Provide context** - Explain why each step matters

---

## Onboarding Flow Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    MERCHANT JOURNEY                          │
└─────────────────────────────────────────────────────────────┘

1. Install App (OAuth)
   ↓
2. Welcome Screen + Billing Setup
   ↓
3. Product Selection (Setup Guide)
   ↓
4. Initial Scan (Automatic)
   ↓
5. First Results Dashboard
   ↓
6. Configure Settings (Optional)
   ↓
7. Ongoing Monitoring
```

### Time to Value
- **Target**: 3-5 minutes from install to first scan
- **Critical Path**: OAuth → Billing → Add 1 product → View first scan

---

## Step-by-Step Merchant Journey

### Phase 1: Installation & Authentication
**Duration**: 30 seconds
**Merchant Actions**: Click "Install App" → Approve permissions

**System Actions**:
- OAuth token exchange
- Create `Shop` record
- Create `ShopSetting` with defaults
- Redirect to app

**Success Criteria**: Merchant lands on app homepage

---

### Phase 2: Welcome & Billing Setup
**Duration**: 1-2 minutes
**Location**: `/billing/create`

#### Welcome Message
```
Welcome to PDP Diagnostics!

Protect your revenue with automated product page monitoring.

We'll help you:
✓ Detect broken add-to-cart buttons
✓ Catch variant selector errors
✓ Monitor page performance
✓ Get instant alerts for issues

Let's get started with your 14-day free trial.
```

**Merchant Actions**:
- Review trial terms (14 days free, then $10/month)
- Click "Start Free Trial"
- Approve subscription (Shopify billing flow)

**System Actions**:
- Call Billing API to create recurring charge
- Set `billing_status` to `trial`
- Track trial start date
- Redirect to setup guide

**Success Criteria**: `billing_status = 'trial'`

---

### Phase 3: Product Selection (Setup Guide)
**Duration**: 2-3 minutes
**Location**: `/` (Homepage with setup guide)

#### Setup Guide Component

Display a prominent setup guide card that tracks completion:

```
┌──────────────────────────────────────────────────────────┐
│  Get Started with PDP Diagnostics                        │
│                                                           │
│  ● Select products to monitor                   [0/3]    │
│    Choose up to 5 of your most important product pages   │
│    → [Add Your First Product]                            │
│                                                           │
│  ○ Configure alert preferences              [Not Started]│
│    Set up email alerts for critical issues               │
│    → [Set Up Alerts]                                     │
│                                                           │
│  ○ Review your first scan                   [Not Started]│
│    See health insights for your product pages            │
│    → [View Dashboard]                                    │
│                                                           │
│  Need help? [View Documentation] [Contact Support]       │
└──────────────────────────────────────────────────────────┘
```

**Step 1: Add Products**

**Merchant Actions**:
1. Click "Add Your First Product"
2. Use Shopify Resource Picker to select 1-5 products
3. Click "Start Monitoring"

**UI Elements**:
- Resource picker modal (Shopify App Bridge)
- Product preview cards
- Slot counter: "2 of 5 slots used"
- Primary CTA: "Start Monitoring These Products"

**System Actions**:
- Create `ProductPage` records
- Queue `ScanPdpJob` for each product
- Update setup guide progress
- Show success message

**Success Message**:
```
✓ Great! Your products are being scanned now.

We're checking your product pages for issues.
This usually takes 1-2 minutes per page.

While you wait, let's configure your alert preferences.
```

---

### Phase 4: Initial Scan (Automatic)
**Duration**: 1-2 minutes per product
**Location**: Background job

**Merchant Experience**:
- See loading states on dashboard
- Progress indicators for each product
- Real-time updates (via Turbo Streams or polling)

**UI States**:

```
Product Card - Scanning State:
┌──────────────────────────────────┐
│ [Product Image]                  │
│ Product Name                     │
│                                  │
│ ⏳ Scanning... 45s elapsed       │
│ [Progress Bar ████████░░]        │
└──────────────────────────────────┘

Product Card - Completed State:
┌──────────────────────────────────┐
│ [Product Image]                  │
│ Product Name                     │
│                                  │
│ ✓ Healthy    [View Details]     │
└──────────────────────────────────┘

Product Card - Issues Found:
┌──────────────────────────────────┐
│ [Product Image]                  │
│ Product Name                     │
│                                  │
│ ⚠ 2 Issues   [Review Issues]    │
└──────────────────────────────────┘
```

**System Actions**:
- Run Puppeteer scan
- Detect issues using rule engine
- Create `Scan` and `Issue` records
- Update `product_page.status`
- Send notifications if issues found

---

### Phase 5: First Results Dashboard
**Duration**: 5-10 minutes (exploration)
**Location**: `/` (Homepage)

#### Homepage Components

**1. Health Overview**
```
┌─────────────────────────────────────────────────────────┐
│  Your Product Page Health                               │
│                                                          │
│  [3] Monitored    [2] Healthy    [1] Warning    [0] Critical
└─────────────────────────────────────────────────────────┘
```

**2. Setup Guide** (if incomplete)
- Show remaining steps
- Update completion status
- Provide quick actions

**3. Critical Issues Alert** (if any)
```
┌─────────────────────────────────────────────────────────┐
│  ⚠ Action Required                                      │
│                                                          │
│  1 critical issue detected:                             │
│  • Missing Add-to-Cart button on "Summer Dress"         │
│    Detected 2 scans ago • [View Details]                │
│                                                          │
│  This could be preventing customers from purchasing.    │
└─────────────────────────────────────────────────────────┘
```

**4. Recent Scans**
- Last 5 scans with status badges
- Timestamps and duration
- Quick link to scan details

**5. Open Issues List**
- Severity-sorted issues
- Product name and issue type
- Occurrence count
- Quick actions: View, Acknowledge

**6. Trial Status Banner** (if in trial)
```
┌─────────────────────────────────────────────────────────┐
│  📅 Trial Active: 12 days remaining                     │
│  Enjoying PDP Diagnostics? Subscribe to continue         │
│  monitoring after your trial ends.                       │
│  [View Plans]                                           │
└─────────────────────────────────────────────────────────┘
```

**Empty State** (no products yet):
```
┌─────────────────────────────────────────────────────────┐
│              Start Monitoring Your Products             │
│                                                          │
│         [Product Page Icon]                             │
│                                                          │
│  Add your first product to start detecting issues       │
│  that could be costing you sales.                       │
│                                                          │
│         [Add Your First Product]                        │
│                                                          │
│  Not sure where to start? Monitor your:                 │
│  • Best-selling products                                │
│  • Highest-traffic pages                                │
│  • Recently updated products                            │
└─────────────────────────────────────────────────────────┘
```

---

### Phase 6: Settings Configuration (Optional)
**Duration**: 2-3 minutes
**Location**: `/settings`

**Merchant Actions**:
1. Configure alert preferences
2. Set alert email address
3. Choose scan frequency
4. Save settings

**Settings Options**:

```
Alert Preferences
─────────────────
☑ Email alerts for critical issues
☑ Shopify admin notifications
☐ Weekly summary reports

Alert Email
───────────
[merchant@store.com]          [Update Email]

Scan Frequency
──────────────
( ) Daily scans (recommended)
(•) Every 2 days
( ) Weekly scans

Monitored Products
──────────────────
Using 3 of 5 slots  [Upgrade Plan]

Subscription Status
───────────────────
Status: Free Trial (12 days remaining)
Next billing date: Feb 14, 2026
Plan: $10/month after trial

[Manage Subscription]
```

**System Actions**:
- Update `ShopSetting` preferences
- Reschedule scan jobs if frequency changed
- Validate email address
- Show success confirmation

---

### Phase 7: Ongoing Monitoring
**Duration**: Continuous

**Automated Actions**:
- Daily/weekly scans (based on settings)
- Issue detection and tracking
- Alert delivery for new issues
- Health status updates

**Merchant Touchpoints**:
- Email alerts for critical issues
- Shopify admin notifications
- Dashboard check-ins
- Weekly summary emails (if enabled)

**Re-engagement Triggers**:
1. **Critical issue detected** → Email + push notification
2. **All pages healthy** → Weekly summary with encouraging message
3. **Trial ending soon** → 3 days before expiration
4. **Scan failed** → Notification with troubleshooting steps
5. **New feature available** → In-app announcement

---

## Homepage Template

### Layout Structure

```
┌──────────────────────────────────────────────────────────────┐
│ [App Name]                    [Settings] [Support] [Account] │
├──────────────────────────────────────────────────────────────┤
│                                                               │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │ Setup Guide (if incomplete)                             │ │
│  │ • Step 1: Select products [2/3 completed]               │ │
│  │ • Step 2: Configure alerts [Not started]                │ │
│  └─────────────────────────────────────────────────────────┘ │
│                                                               │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │ Health Overview                                          │ │
│  │ [3 Monitored] [2 Healthy] [1 Warning] [0 Critical]      │ │
│  └─────────────────────────────────────────────────────────┘ │
│                                                               │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │ Critical Issues Alert (if any)                           │ │
│  │ ⚠ 1 issue requires your attention                       │ │
│  └─────────────────────────────────────────────────────────┘ │
│                                                               │
│  ┌──────────────────────────┐  ┌──────────────────────────┐ │
│  │ Open Issues              │  │ Recent Scans             │ │
│  │                          │  │                          │ │
│  │ [Issue list]             │  │ [Scan list]              │ │
│  │                          │  │                          │ │
│  └──────────────────────────┘  └──────────────────────────┘ │
│                                                               │
│  ┌─────────────────────────────────────────────────────────┐ │
│  │ Quick Actions                                            │ │
│  │ [Add Products] [Run Manual Scan] [View All Issues]      │ │
│  └─────────────────────────────────────────────────────────┘ │
│                                                               │
└──────────────────────────────────────────────────────────────┘
```

### Component Priority

**First-time users** (no products added):
1. Setup Guide (most prominent)
2. Empty state with CTA
3. Quick action to add products

**Active users** (products added, scans running):
1. Critical issue alerts (if any)
2. Health overview
3. Setup guide (if incomplete)
4. Recent activity

**Established users** (setup complete):
1. Health overview
2. Critical issue alerts
3. Recent scans and issues
4. Quick actions

---

## Setup Guide Component

### Shopify Official Design Guidelines

Based on Shopify's official homepage patterns:

**Onboarding Requirements:**
- ✅ Must be brief and direct with clear instructions
- ✅ Only request information that's necessary
- ✅ Make it dismissible if not essential
- ✅ Maximum of 5 steps (avoid user drop-off)
- ✅ Allow completion at a later time for long/complex onboarding

**Components Used:**
`Badge`, `Banner`, `Box`, `Button`, `Checkbox`, `Clickable`, `Divider`, `Grid`, `Heading`, `Image`, `Link`, `Paragraph`, `Section`, `Stack`, `Text`

---

### Implementation - Rails/ERB Pattern

#### Step Definitions (Ruby Model/Helper)

```ruby
# app/models/shop_setting.rb or app/helpers/onboarding_helper.rb
module OnboardingHelper
  def setup_steps
    [
      {
        id: 'select_products',
        label: 'Select products to monitor',
        description: 'Choose up to 5 of your most important product pages for monitoring',
        completed: shop.product_pages.count > 0,
        cta_text: shop.product_pages.count > 0 ? 'Add more products' : 'Add your first product',
        cta_url: new_product_page_path,
        cta_variant: 'primary',
        progress: "#{shop.product_pages.count}/5"
      },
      {
        id: 'configure_alerts',
        label: 'Configure alert preferences',
        description: 'Set up email and Shopify admin notifications for critical issues',
        completed: alert_email.present?,
        cta_text: 'Set up alerts',
        cta_url: settings_path,
        cta_variant: 'primary',
        progress: alert_email.present? ? 'Complete' : 'Not started'
      },
      {
        id: 'review_first_scan',
        label: 'Review your first scan',
        description: 'View health insights and detected issues for your product pages',
        completed: shop.scans.completed.any?,
        cta_text: 'View results',
        cta_url: root_path,
        cta_variant: 'primary',
        progress: shop.scans.completed.any? ? 'Complete' : 'Pending scan'
      }
    ]
  end

  def setup_progress
    completed = setup_steps.count { |step| step[:completed] }
    total = setup_steps.count
    { completed: completed, total: total, percentage: (completed.to_f / total * 100).round }
  end

  def setup_complete?
    setup_progress[:completed] == setup_progress[:total]
  end
end
```

---

### Full Setup Guide Component (Official Shopify Pattern)

```erb
<!-- app/views/shared/_setup_guide.html.erb -->
<%#
  Setup Guide Component - Shopify Homepage Pattern
  Only show if setup is incomplete and not dismissed
  Store dismissal in shop_settings.setup_guide_dismissed_at
%>

<% unless setup_complete? || @shop_setting.setup_guide_dismissed_at.present? %>
  <s-section id="setup-guide-section">
    <s-grid gap="small">

      <!-- Header with progress -->
      <s-grid gap="small-200">
        <s-grid gridTemplateColumns="1fr auto auto" gap="small-300" alignItems="center">
          <s-heading>Setup Guide</s-heading>

          <!-- Dismiss button -->
          <s-button
            accessibilityLabel="Dismiss Guide"
            onClick="dismissSetupGuide()"
            variant="tertiary"
            tone="neutral"
            icon="x"
          ></s-button>

          <!-- Collapse/Expand button -->
          <s-button
            id="toggle-guide-button"
            accessibilityLabel="Toggle setup guide"
            onClick="toggleSetupGuide()"
            variant="tertiary"
            tone="neutral"
            icon="chevron-up"
          ></s-button>
        </s-grid>

        <s-paragraph>
          Use this personalized guide to get your store ready for product page monitoring.
        </s-paragraph>

        <s-paragraph color="subdued">
          <%= setup_progress[:completed] %> out of <%= setup_progress[:total] %> steps completed
        </s-paragraph>
      </s-grid>

      <!-- Steps Container -->
      <s-box
        id="steps-container"
        borderRadius="base"
        border="base"
        background="base"
      >

        <% setup_steps.each_with_index do |step, index| %>
          <!-- Step <%= index + 1 %> -->
          <s-box>
            <s-grid gridTemplateColumns="1fr auto" gap="base" padding="small">
              <!-- Checkbox -->
              <s-checkbox
                label="<%= step[:label] %>"
                <%= 'checked' if step[:completed] %>
                disabled
              ></s-checkbox>

              <!-- Toggle details button -->
              <s-button
                id="toggle-step<%= index %>-button"
                onClick="toggleStep(<%= index %>)"
                accessibilityLabel="Toggle step <%= index + 1 %> details"
                variant="tertiary"
                icon="chevron-down"
              ></s-button>
            </s-grid>

            <!-- Step details (initially hidden) -->
            <s-box
              id="step<%= index %>-details"
              padding="small"
              paddingBlockStart="none"
              style="display: none;"
            >
              <s-box padding="base" background="subdued" borderRadius="base">
                <s-grid gridTemplateColumns="1fr auto" gap="base" alignItems="center">
                  <!-- Content -->
                  <s-grid gap="small-200">
                    <s-paragraph>
                      <%= step[:description] %>
                    </s-paragraph>

                    <s-stack direction="inline" gap="small-200">
                      <s-button variant="<%= step[:cta_variant] %>" href="<%= step[:cta_url] %>">
                        <%= step[:cta_text] %>
                      </s-button>

                      <% if step[:id] == 'select_products' %>
                        <s-button variant="tertiary" tone="neutral" href="/docs/selecting-products">
                          Product selection tips
                        </s-button>
                      <% elsif step[:id] == 'configure_alerts' %>
                        <s-button variant="tertiary" tone="neutral" href="/docs/alerts">
                          Alert best practices
                        </s-button>
                      <% end %>
                    </s-stack>
                  </s-grid>

                  <!-- Illustration -->
                  <s-box maxBlockSize="80px" maxInlineSize="80px">
                    <s-image
                      src="<%= asset_path("setup-step-#{step[:id]}.svg") %>"
                      alt="<%= step[:label] %> illustration"
                    ></s-image>
                  </s-box>
                </s-grid>
              </s-box>
            </s-box>
          </s-box>

          <!-- Divider between steps (not after last step) -->
          <% unless index == setup_steps.count - 1 %>
            <s-divider></s-divider>
          <% end %>
        <% end %>

      </s-box>
    </s-grid>
  </s-section>

  <!-- JavaScript for interactive behavior -->
  <script>
    // Store state in window object
    window.setupGuideState = {
      expanded: true,
      steps: [false, false, false] // Track which steps are expanded
    };

    function toggleSetupGuide() {
      const container = document.getElementById('steps-container');
      const button = document.getElementById('toggle-guide-button');

      window.setupGuideState.expanded = !window.setupGuideState.expanded;

      container.style.display = window.setupGuideState.expanded ? 'block' : 'none';
      button.setAttribute('icon', window.setupGuideState.expanded ? 'chevron-up' : 'chevron-down');
    }

    function toggleStep(stepIndex) {
      const details = document.getElementById(`step${stepIndex}-details`);
      const button = document.getElementById(`toggle-step${stepIndex}-button`);

      window.setupGuideState.steps[stepIndex] = !window.setupGuideState.steps[stepIndex];

      details.style.display = window.setupGuideState.steps[stepIndex] ? 'block' : 'none';
      button.setAttribute('icon', window.setupGuideState.steps[stepIndex] ? 'chevron-up' : 'chevron-down');
    }

    function dismissSetupGuide() {
      // Make AJAX call to store dismissal
      fetch('/settings/dismiss_setup_guide', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': document.querySelector('[name="csrf-token"]').content
        }
      }).then(() => {
        document.getElementById('setup-guide-section').style.display = 'none';
      });
    }
  </script>
<% end %>
```

---

### Controller Action for Dismissal

```ruby
# app/controllers/settings_controller.rb
class SettingsController < AuthenticatedController
  def dismiss_setup_guide
    @shop_setting.update(setup_guide_dismissed_at: Time.current)
    head :ok
  end
end
```

```ruby
# config/routes.rb
post 'settings/dismiss_setup_guide', to: 'settings#dismiss_setup_guide'
```

### Dismissal Behavior

**Option 1: Auto-dismiss**
- Hide setup guide when 100% complete
- Show subtle "Setup complete" banner
- Provide way to access setup steps in settings

**Option 2: Manual dismiss**
- Allow merchants to dismiss guide
- Store dismissal in `shop_settings.setup_guide_dismissed_at`
- Show "Review setup" link in settings

**Recommended**: Auto-dismiss + persistent "Getting Started" section in Help menu

---

## UI/UX Implementation Details

### Polaris Components

Use Shopify Polaris Web Components throughout:

```html
<!-- Page structure -->
<s-page title="Product Page Diagnostics">
  <s-layout>
    <s-layout-section>
      <!-- Main content -->
    </s-layout-section>
  </s-layout>
</s-page>

<!-- Cards for content sections -->
<s-card sectioned>
  <s-heading>Section Title</s-heading>
  <s-text>Content here</s-text>
</s-card>

<!-- Status badges -->
<s-badge status="success">Healthy</s-badge>
<s-badge status="warning">Warning</s-badge>
<s-badge status="critical">Critical</s-badge>
<s-badge status="info">Scanning</s-badge>

<!-- Buttons -->
<s-button variant="primary">Primary Action</s-button>
<s-button>Secondary Action</s-button>
<s-button variant="plain">Tertiary Action</s-button>

<!-- Resource Picker (Shopify App Bridge) -->
<script>
  const picker = shopify.resourcePicker({
    type: 'product',
    multiple: true,
    selectionIds: [], // Already selected
    action: 'select'
  });

  picker.subscribe('selection', (selection) => {
    // Handle selected products
  });
</script>
```

### Loading States

Show progress for all async operations:

```html
<!-- Scanning state -->
<s-spinner size="small"></s-spinner> Scanning products...

<!-- Skeleton loading -->
<s-skeleton-body-text lines="3"></s-skeleton-body-text>

<!-- Progress bar -->
<s-progress-bar value="60" max="100"></s-progress-bar>
```

### Empty States

Provide clear guidance when no data:

```html
<s-empty-state
  heading="No products monitored yet"
  image="/empty-state-products.svg"
>
  <p>Add your first product to start monitoring for issues</p>
  <s-button variant="primary" href="/product_pages/new">
    Add Product
  </s-button>
</s-empty-state>
```

### Error States

Handle errors gracefully:

```html
<s-banner status="critical" dismissible>
  <s-heading>Scan failed</s-heading>
  <p>We couldn't access your product page. This might be due to:</p>
  <ul>
    <li>Password protection enabled</li>
    <li>Geographic restrictions</li>
    <li>Temporary connectivity issues</li>
  </ul>
  <s-button>Retry Scan</s-button>
  <s-button variant="plain">Contact Support</s-button>
</s-banner>
```

### Success States

Celebrate merchant achievements:

```html
<s-banner status="success" dismissible>
  ✓ Great! Your products are now being monitored.
  We'll alert you if any issues are detected.
</s-banner>
```

---

## Complete Homepage Implementation (Official Shopify Pattern)

Below is a complete homepage implementation following Shopify's official patterns for the PDP Diagnostics app:

```erb
<!-- app/views/home/index.html.erb -->
<s-page>
  <!-- Primary and secondary actions in page header -->
  <s-button slot="primary-action" href="<%= new_product_page_path %>">
    Add product
  </s-button>
  <s-button slot="secondary-actions" href="<%= scans_path %>">
    View all scans
  </s-button>
  <s-button slot="secondary-actions" href="<%= settings_path %>">
    Settings
  </s-button>

  <!-- === Trial Banner === -->
  <!-- Use banners sparingly. Only one banner should be visible at a time. -->
  <% if @shop_setting.billing_status == 'trial' %>
    <s-banner tone="info">
      Trial Active: <%= @shop_setting.trial_days_remaining %> days remaining.
      <s-link href="<%= billing_path %>">Subscribe now</s-link> to continue monitoring after your trial ends.
    </s-banner>
  <% end %>

  <!-- === Critical Issues Banner === -->
  <% if @critical_issues.any? %>
    <s-banner tone="critical">
      <strong>⚠ <%= pluralize(@critical_issues.count, 'critical issue') %> detected!</strong><br>
      These issues may be preventing customers from purchasing.
      <s-link href="<%= issues_path(severity: 'high') %>">Review issues</s-link>
    </s-banner>
  <% end %>

  <!-- === Setup Guide === -->
  <%= render 'shared/setup_guide' %>

  <!-- === Health Overview Metrics === -->
  <s-section padding="small">
    <s-grid
      gridTemplateColumns="@container (inline-size <= 400px) 1fr, 1fr auto 1fr auto 1fr"
      gap="small"
    >
      <s-clickable
        href="<%= product_pages_path %>"
        paddingBlock="small-400"
        paddingInline="small-100"
        borderRadius="base"
      >
        <s-grid gap="small-300">
          <s-heading>Monitored Pages</s-heading>
          <s-stack direction="inline" gap="small-200">
            <s-text><%= @shop.product_pages.count %></s-text>
            <s-badge tone="info"><%= @shop.product_pages.count %>/5</s-badge>
          </s-stack>
        </s-grid>
      </s-clickable>

      <s-divider direction="block"></s-divider>

      <s-clickable
        href="<%= product_pages_path(status: 'healthy') %>"
        paddingBlock="small-400"
        paddingInline="small-100"
        borderRadius="base"
      >
        <s-grid gap="small-300">
          <s-heading>Healthy</s-heading>
          <s-stack direction="inline" gap="small-200">
            <s-text><%= @healthy_count %></s-text>
            <s-badge tone="success" icon="check-circle">
              <%= percentage(@healthy_count, @shop.product_pages.count) %>%
            </s-badge>
          </s-stack>
        </s-grid>
      </s-clickable>

      <s-divider direction="block"></s-divider>

      <s-clickable
        href="<%= issues_path(status: 'open') %>"
        paddingBlock="small-400"
        paddingInline="small-100"
        borderRadius="base"
      >
        <s-grid gap="small-300">
          <s-heading>Open Issues</s-heading>
          <s-stack direction="inline" gap="small-200">
            <s-text><%= @open_issues_count %></s-text>
            <% if @open_issues_count > 0 %>
              <s-badge tone="warning"><%= @open_issues_count %> active</s-badge>
            <% else %>
              <s-badge tone="success">All clear</s-badge>
            <% end %>
          </s-stack>
        </s-grid>
      </s-clickable>
    </s-grid>
  </s-section>

  <!-- === Empty State (if no products) === -->
  <% if @shop.product_pages.count == 0 %>
    <s-section>
      <s-box
        padding="extra-large"
        background="base"
        border="base"
        borderRadius="base"
        textAlign="center"
      >
        <s-grid gap="base" justifyItems="center">
          <s-box maxInlineSize="200px">
            <s-image
              src="<%= asset_path('empty-state-products.svg') %>"
              alt="No products monitored"
            ></s-image>
          </s-box>

          <s-heading>Start monitoring your product pages</s-heading>

          <s-paragraph color="subdued">
            Add your first product to start detecting issues that could be costing you sales.
          </s-paragraph>

          <s-button variant="primary" href="<%= new_product_page_path %>">
            Add your first product
          </s-button>

          <s-grid gap="small-200" textAlign="left">
            <s-text variant="headingSm">Not sure where to start? Monitor your:</s-text>
            <s-paragraph color="subdued">• Best-selling products</s-paragraph>
            <s-paragraph color="subdued">• Highest-traffic pages</s-paragraph>
            <s-paragraph color="subdued">• Recently updated products</s-paragraph>
          </s-grid>
        </s-grid>
      </s-box>
    </s-section>
  <% else %>

    <!-- === Open Issues Section === -->
    <% if @open_issues.any? %>
      <s-section>
        <s-grid gridTemplateColumns="1fr auto" alignItems="center" gap="base">
          <s-heading>Open Issues</s-heading>
          <s-link href="<%= issues_path %>">View all</s-link>
        </s-grid>

        <s-grid gap="small">
          <% @open_issues.first(5).each do |issue| %>
            <s-box border="base" borderRadius="base" padding="base">
              <s-grid
                gridTemplateColumns="auto 1fr auto"
                gap="base"
                alignItems="center"
              >
                <!-- Severity badge -->
                <% if issue.severity == 'high' %>
                  <s-badge tone="critical" icon="alert-triangle">Critical</s-badge>
                <% elsif issue.severity == 'medium' %>
                  <s-badge tone="warning">Warning</s-badge>
                <% else %>
                  <s-badge tone="info">Info</s-badge>
                <% end %>

                <!-- Issue details -->
                <s-grid gap="small-200">
                  <s-text variant="headingSm">
                    <%= issue.issue_type.humanize %> on <%= issue.product_page.title %>
                  </s-text>
                  <s-text color="subdued">
                    Detected <%= time_ago_in_words(issue.first_detected_at) %> ago
                    · Occurred <%= pluralize(issue.occurrence_count, 'time') %>
                  </s-text>
                </s-grid>

                <!-- Action button -->
                <s-button href="<%= issue_path(issue) %>">
                  Review
                </s-button>
              </s-grid>
            </s-box>
          <% end %>
        </s-grid>
      </s-section>
    <% end %>

    <!-- === Recent Scans Section === -->
    <s-section>
      <s-grid gridTemplateColumns="1fr auto" alignItems="center" gap="base">
        <s-heading>Recent Scans</s-heading>
        <s-link href="<%= scans_path %>">View all</s-link>
      </s-grid>

      <s-grid gridTemplateColumns="repeat(auto-fit, minmax(240px, 1fr))" gap="base">
        <% @recent_scans.first(3).each do |scan| %>
          <s-box border="base" borderRadius="base" overflow="hidden">
            <!-- Product image -->
            <s-clickable href="<%= scan_path(scan) %>">
              <s-image
                aspectRatio="16/9"
                objectFit="cover"
                alt="<%= scan.product_page.title %>"
                src="<%= scan.product_page.image_url %>"
              ></s-image>
            </s-clickable>

            <s-divider></s-divider>

            <!-- Scan details -->
            <s-grid
              gridTemplateColumns="1fr auto"
              background="base"
              padding="small"
              gap="small"
              alignItems="center"
            >
              <s-grid gap="small-200">
                <s-heading><%= scan.product_page.title %></s-heading>
                <s-text color="subdued">
                  <%= time_ago_in_words(scan.completed_at) %> ago
                </s-text>
              </s-grid>

              <% if scan.status == 'completed' %>
                <% if scan.issues_count == 0 %>
                  <s-badge tone="success">Healthy</s-badge>
                <% else %>
                  <s-badge tone="warning"><%= scan.issues_count %> issues</s-badge>
                <% end %>
              <% elsif scan.status == 'running' %>
                <s-badge tone="info">Scanning...</s-badge>
              <% else %>
                <s-badge tone="critical">Failed</s-badge>
              <% end %>
            </s-grid>
          </s-box>
        <% end %>
      </s-grid>
    </s-section>

    <!-- === Callout Card: Upgrade Prompt === -->
    <% if @shop.product_pages.count >= 4 && @shop_setting.billing_status == 'trial' %>
      <s-section id="upgrade-callout">
        <s-grid
          gridTemplateColumns="1fr auto"
          gap="small-400"
          alignItems="start"
        >
          <s-grid
            gridTemplateColumns="@container (inline-size <= 480px) 1fr, auto auto"
            gap="base"
            alignItems="center"
          >
            <s-grid gap="small-200">
              <s-heading>You're using 4 of 5 monitoring slots</s-heading>
              <s-paragraph>
                Upgrade to the Pro plan to monitor unlimited product pages and get
                advanced alerting features.
              </s-paragraph>
              <s-stack direction="inline" gap="small-200">
                <s-button variant="primary" href="<%= billing_path %>">
                  View plans
                </s-button>
                <s-button tone="neutral" variant="tertiary" href="/docs/pricing">
                  Learn more
                </s-button>
              </s-stack>
            </s-grid>
          </s-grid>
          <s-button
            onClick="document.getElementById('upgrade-callout').style.display='none'"
            icon="x"
            tone="neutral"
            variant="tertiary"
            accessibilityLabel="Dismiss upgrade prompt"
          ></s-button>
        </s-grid>
      </s-section>
    <% end %>

  <% end %>

  <!-- === Quick Actions Footer === -->
  <s-section>
    <s-box
      padding="base"
      background="subdued"
      borderRadius="base"
    >
      <s-grid gap="small-400">
        <s-heading>Quick Actions</s-heading>
        <s-stack direction="inline" gap="small-200" wrap>
          <s-button href="<%= new_product_page_path %>">
            Add products
          </s-button>
          <s-button href="<%= scans_path(trigger: 'manual') %>" variant="secondary">
            Run manual scan
          </s-button>
          <s-button href="<%= issues_path %>" variant="secondary">
            View all issues
          </s-button>
          <s-button href="<%= settings_path %>" variant="tertiary" tone="neutral">
            Configure settings
          </s-button>
        </s-stack>
      </s-grid>
    </s-box>
  </s-section>

</s-page>
```

### Controller Setup

```ruby
# app/controllers/home_controller.rb
class HomeController < AuthenticatedController
  def index
    @shop = current_shop
    @shop_setting = @shop.shop_setting

    # Metrics
    @healthy_count = @shop.product_pages.healthy.count
    @open_issues_count = @shop.issues.open.count
    @critical_issues = @shop.issues.open.high_severity.limit(5)

    # Recent activity
    @open_issues = @shop.issues.open.order(severity: :desc, created_at: :desc).limit(5)
    @recent_scans = @shop.scans.completed.order(completed_at: :desc).limit(6)
  end

  private

  def percentage(part, whole)
    return 0 if whole.zero?
    ((part.to_f / whole) * 100).round
  end
  helper_method :percentage
end
```

---

## Best Practices

### Shopify Official Guidelines Summary

**From Shopify Homepage Pattern Documentation:**

1. **Onboarding Must Be:**
   - Brief and direct
   - Request only necessary information
   - Dismissible if not essential
   - Maximum 5 steps
   - Allow later completion for complex flows

2. **Visual Design:**
   - Responsive across all screen sizes
   - Looser spacing for low-density layouts
   - Tighter spacing for high-density layouts
   - High-resolution photos and images

3. **Homepage Purpose:**
   - Teach merchants how to use the app (onboarding, guides)
   - Display app functionalities (CTAs, resource tables)
   - Show updates (status banners, news)
   - Provide daily value

---

### 1. Progressive Disclosure

**Do**:
- Show most critical information first
- Reveal advanced features gradually
- Use "Learn more" links for details

**Don't**:
- Overwhelm with all features at once
- Hide critical setup steps
- Assume merchant knowledge

### 2. Clear Calls-to-Action

**Do**:
- Use action-oriented button text ("Add Your First Product")
- Make primary actions visually prominent
- Explain what happens after clicking

**Don't**:
- Use vague CTAs ("Click here", "Continue")
- Present too many equal-priority actions
- Skip confirmation messages

### 3. Contextual Help

**Do**:
- Provide inline help text
- Link to relevant documentation
- Offer support contact option

**Don't**:
- Require external documentation to proceed
- Use technical jargon without explanation
- Hide help resources

### 4. Feedback & Validation

**Do**:
- Show immediate feedback for actions
- Validate inputs before submission
- Explain validation errors clearly

**Don't**:
- Submit forms without validation
- Use generic error messages
- Leave merchants guessing about success

### 5. Mobile Optimization

**Do**:
- Test on mobile devices
- Use responsive Polaris components
- Ensure touch targets are adequate

**Don't**:
- Design desktop-only experiences
- Use hover-dependent interactions
- Ignore mobile merchant workflows

### 6. Performance

**Do**:
- Show loading states for async operations
- Optimize initial page load
- Cache frequently accessed data

**Don't**:
- Block interactions during loading
- Load all data synchronously
- Skip loading indicators

### 7. Accessibility

**Do**:
- Use semantic HTML
- Provide alt text for images
- Ensure keyboard navigation

**Don't**:
- Rely on color alone for status
- Skip focus management
- Ignore screen reader compatibility

---

## Onboarding Success Metrics

### Track These KPIs

**Setup Completion**:
- % of installs that add ≥1 product
- Time to first product added
- % completing full setup guide

**Engagement**:
- % viewing first scan results
- % configuring alert settings
- % returning within 7 days

**Trial Conversion**:
- % of trials converting to paid
- Average products monitored per merchant
- % receiving alerts during trial

**Drop-off Points**:
- Where merchants abandon setup
- Common error scenarios
- Support ticket themes

### Optimization Targets

- **≥80%** of installs add first product
- **≤3 minutes** average time to first scan
- **≥60%** trial-to-paid conversion
- **≥90%** setup guide completion

---

## Future Enhancements

### Phase 2 Onboarding Additions

1. **Interactive Demo**
   - Sandbox mode with sample products
   - Show example issues and alerts
   - No setup required to see value

2. **Onboarding Checklist Widget**
   - Persistent sidebar widget
   - Track completion across sessions
   - Gamification with progress badges

3. **Contextual Tooltips**
   - Highlight new features
   - Guide through first use
   - Dismissible and non-intrusive

4. **Video Walkthrough**
   - Embedded 2-minute overview
   - Step-by-step setup guide
   - Best practices tips

5. **Smart Recommendations**
   - Suggest products to monitor based on traffic
   - Recommend scan frequency based on update patterns
   - Auto-configure settings from store data

6. **Email Nurture Series**
   - Day 1: Welcome + setup reminder
   - Day 3: Feature highlights
   - Day 7: Success stories
   - Day 12: Trial ending soon

---

## Implementation Checklist

### Phase 1: Core Onboarding (MVP)
- [x] OAuth installation flow
- [x] Billing setup with trial
- [x] Product selection with resource picker
- [x] Initial scan automation
- [x] Basic dashboard with health overview
- [ ] Setup guide component
- [ ] Empty states for all views
- [ ] Success/error messaging
- [ ] Trial status banner

### Phase 2: Enhanced UX
- [ ] Interactive demo mode
- [ ] Onboarding progress widget
- [ ] Contextual tooltips
- [ ] Video walkthrough
- [ ] Email nurture sequence
- [ ] Smart product recommendations
- [ ] Advanced settings wizard

### Phase 3: Optimization
- [ ] A/B test setup flow variations
- [ ] Track drop-off analytics
- [ ] Optimize time-to-value
- [ ] Personalized onboarding paths
- [ ] In-app messaging system

---

## Support Resources

### For Merchants
- **Help Center**: In-app documentation
- **Setup Guide**: Step-by-step walkthrough
- **Video Tutorials**: Visual learning resources
- **Live Chat**: Immediate support during setup
- **Email Support**: support@pdpdiagnostics.app

### For Developers
- **Shopify Polaris**: https://polaris.shopify.com/
- **App Bridge Docs**: https://shopify.dev/docs/api/app-bridge-library
- **Resource Picker**: https://shopify.dev/docs/api/app-bridge-library/apis/resource-picker
- **Billing API**: https://shopify.dev/docs/apps/billing

---

## Conclusion

This onboarding guide provides a comprehensive framework for merchant success with PDP Diagnostics. By following Shopify's UX patterns and focusing on time-to-value, merchants can:

1. **Install and setup in under 5 minutes**
2. **See immediate value from first scan**
3. **Understand product health at a glance**
4. **Configure preferences with ease**
5. **Trust the app to protect revenue**

The setup guide component, progressive disclosure, and clear CTAs ensure merchants never feel lost or overwhelmed. Combined with automated scanning and proactive alerts, the onboarding experience sets the foundation for long-term engagement and retention.

---

## References

This guide is based on official Shopify documentation and best practices:

1. **Shopify App Homepage Pattern**
   - URL: https://shopify.dev/docs/api/app-home/patterns/templates/homepage
   - Components: Badge, Banner, Box, Button, Checkbox, Clickable, Divider, Grid, Heading, Image, Link, Paragraph, Section, Stack, Text
   - Key Guidelines: Onboarding must be brief (max 5 steps), dismissible, and request only necessary information

2. **Shopify App Onboarding Guidelines**
   - URL: https://shopify.dev/docs/apps/design/user-experience/onboarding
   - Best Practices: Self-guided, easy to follow, allow later completion
   - Visual Design: Responsive, proper spacing, high-resolution assets

3. **Shopify Setup Guide Composition**
   - URL: https://shopify.dev/docs/api/app-home/patterns/compositions/setup-guide
   - Pattern: Checkbox-based progress tracking with expandable step details
   - Behavior: Dismissible, collapsible, tracks completion state

4. **Shopify Polaris Design System**
   - URL: https://polaris.shopify.com/
   - Web Components: Full Polaris component library for embedded apps
   - Patterns: Official UX patterns and templates

5. **Built for Shopify Requirements**
   - URL: https://shopify.dev/docs/apps/launch/built-for-shopify/requirements
   - Quality Standards: Performance, UX, accessibility requirements

---

**Document Version**: 2.0
**Last Updated**: 2026-01-31
**Maintained By**: Development Team

**Changelog**:
- v2.0 (2026-01-31): Added official Shopify patterns, complete homepage implementation, setup guide code examples
- v1.0 (2026-01-31): Initial merchant onboarding framework
