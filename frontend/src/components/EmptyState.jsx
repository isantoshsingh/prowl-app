/**
 * EmptyState component for displaying empty states
 */

export default function EmptyState({
  title = 'No data found',
  description,
  action,
  actionLabel,
  icon = '📋'
}) {
  return (
    <div className="empty-state">
      <div className="empty-state__icon">{icon}</div>
      <div className="empty-state__title">{title}</div>
      {description && (
        <div className="empty-state__description">{description}</div>
      )}
      {action && actionLabel && (
        <s-button onClick={action}>{actionLabel}</s-button>
      )}
    </div>
  );
}
