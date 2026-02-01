/**
 * StatCard component for displaying statistics using Polaris Web Components
 */

export default function StatCard({ label, value, variant }) {
  // Map variant to Polaris tone
  const getTone = () => {
    switch (variant) {
      case 'success': return 'success';
      case 'warning': return 'warning';
      case 'critical': return 'critical';
      default: return undefined;
    }
  };

  const tone = getTone();

  return (
    <s-card>
      <s-box padding="400">
        <s-block-stack gap="200">
          <s-text variant="bodySm" tone="subdued">{label}</s-text>
          <s-text variant="headingLg" tone={tone}>{value}</s-text>
        </s-block-stack>
      </s-box>
    </s-card>
  );
}
