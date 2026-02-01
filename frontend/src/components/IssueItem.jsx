/**
 * IssueItem component using Polaris Web Components
 */

import { useNavigate } from 'react-router-dom';

export default function IssueItem({ issue }) {
  const navigate = useNavigate();

  const severityClass = issue.severity === 'high' ? 'severity-dot--critical' :
                        issue.severity === 'medium' ? 'severity-dot--warning' : 'severity-dot--info';
  const timeAgo = formatTimeAgo(issue.last_detected_at || issue.created_at);

  return (
    <s-resource-item onClick={() => navigate(`/issues/${issue.id}`)}>
      <s-inline-stack gap="300" block-align="center" wrap={false}>
        <div className={`severity-dot ${severityClass}`} />
        <s-box min-width="0">
          <s-block-stack gap="100">
            <s-text variant="bodyMd" fontWeight="medium" truncate>{issue.title}</s-text>
            <s-text variant="bodySm" tone="subdued">
              {issue.product_page?.title && `${issue.product_page.title} • `}
              {timeAgo}
              {issue.occurrence_count > 1 && ` • ${issue.occurrence_count} occurrences`}
            </s-text>
          </s-block-stack>
        </s-box>
      </s-inline-stack>
    </s-resource-item>
  );
}

function formatTimeAgo(dateString) {
  if (!dateString) return 'Unknown';

  const date = new Date(dateString);
  const now = new Date();
  const diffMs = now - date;
  const diffMins = Math.floor(diffMs / 60000);
  const diffHours = Math.floor(diffMs / 3600000);
  const diffDays = Math.floor(diffMs / 86400000);

  if (diffMins < 1) return 'Just now';
  if (diffMins < 60) return `${diffMins}m ago`;
  if (diffHours < 24) return `${diffHours}h ago`;
  if (diffDays < 7) return `${diffDays}d ago`;

  return date.toLocaleDateString();
}
