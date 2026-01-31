/**
 * StatusBadge component using Shopify Polaris Web Components
 * Displays status badges for various states (healthy, warning, critical, etc.)
 */

const STATUS_TONES = {
  // Product page statuses
  healthy: 'success',
  warning: 'warning',
  critical: 'critical',
  pending: 'default',
  error: 'critical',

  // Issue statuses
  open: 'critical',
  acknowledged: 'warning',
  resolved: 'success',

  // Scan statuses
  running: 'info',
  completed: 'success',
  failed: 'critical',

  // Severity
  high: 'critical',
  medium: 'warning',
  low: 'default',

  // Billing
  trial: 'info',
  active: 'success',
  cancelled: 'warning',
  expired: 'critical'
};

export default function StatusBadge({ status, children }) {
  const tone = STATUS_TONES[status?.toLowerCase()] || 'default';
  const label = children || status?.replace(/_/g, ' ').replace(/\b\w/g, c => c.toUpperCase());

  return (
    <s-badge tone={tone}>{label}</s-badge>
  );
}
