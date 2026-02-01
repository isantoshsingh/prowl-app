/**
 * BillingBanner component using Polaris Web Components
 */

export default function BillingBanner({ billingStatus, trialDaysRemaining, onSubscribe }) {
  if (billingStatus === 'active') {
    return null;
  }

  const isTrial = billingStatus === 'trial';
  const isExpired = billingStatus === 'expired' || billingStatus === 'cancelled';

  // Don't show banner if trial has plenty of time left
  if (isTrial && trialDaysRemaining > 7) {
    return null;
  }

  const title = isExpired
    ? 'Your subscription has ended'
    : `${trialDaysRemaining} days left in your free trial`;

  const description = isExpired
    ? 'Subscribe to continue monitoring your product pages.'
    : 'Subscribe now to ensure uninterrupted monitoring.';

  return (
    <s-banner tone={isExpired ? 'critical' : 'warning'} title={title}>
      <s-block-stack gap="300">
        <s-text>{description}</s-text>
        {onSubscribe && (
          <s-button onClick={onSubscribe}>Subscribe Now - $10/month</s-button>
        )}
      </s-block-stack>
    </s-banner>
  );
}
