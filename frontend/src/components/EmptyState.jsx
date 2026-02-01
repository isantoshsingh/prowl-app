/**
 * EmptyState component using Polaris Web Components
 */

export default function EmptyState({
  title = 'No data found',
  description,
  action,
  actionLabel
}) {
  return (
    <s-card>
      <s-empty-state>
        <s-text variant="headingMd">{title}</s-text>
        {description && (
          <s-box padding-block-start="200">
            <s-text tone="subdued">{description}</s-text>
          </s-box>
        )}
        {action && actionLabel && (
          <s-box padding-block-start="400">
            <s-button onClick={action}>{actionLabel}</s-button>
          </s-box>
        )}
      </s-empty-state>
    </s-card>
  );
}
