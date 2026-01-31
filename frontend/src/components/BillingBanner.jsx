/**
 * BillingBanner component for trial/subscription status
 */

export default function BillingBanner({ billingStatus, trialDaysRemaining, onSubscribe }) {
  if (billingStatus === 'active') {
    return null;
  }

  const isTrial = billingStatus === 'trial';
  const isExpired = billingStatus === 'expired' || billingStatus === 'cancelled';

  if (isTrial && trialDaysRemaining > 7) {
    return null;
  }

  return (
    <s-banner
      tone={isExpired ? 'critical' : 'warning'}
      title={
        isExpired
          ? 'Your subscription has ended'
          : `${trialDaysRemaining} days left in your free trial`
      }
    >
      <s-text>
        {isExpired
          ? 'Subscribe to continue monitoring your product pages.'
          : 'Subscribe now to ensure uninterrupted monitoring.'}
      </s-text>
      {onSubscribe && (
        <s-button-group>
          <s-button variant="primary" onClick={onSubscribe}>
            Subscribe Now
          </s-button>
        </s-button-group>
      )}
    </s-banner>
  );
}
