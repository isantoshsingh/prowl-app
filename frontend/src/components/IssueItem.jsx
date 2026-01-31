/**
 * IssueItem component for displaying issues in lists
 */

import { useNavigate } from 'react-router-dom';

export default function IssueItem({ issue }) {
  const navigate = useNavigate();

  const severityClass = `issue-item__severity--${issue.severity}`;
  const timeAgo = formatTimeAgo(issue.last_detected_at || issue.created_at);

  return (
    <div
      className="issue-item clickable-row"
      onClick={() => navigate(`/issues/${issue.id}`)}
    >
      <div className={`issue-item__severity ${severityClass}`} />
      <div className="issue-item__content">
        <div className="issue-item__title">{issue.title}</div>
        <div className="issue-item__meta">
          {issue.product_page?.title && (
            <span>{issue.product_page.title} • </span>
          )}
          <span>{timeAgo}</span>
          {issue.occurrence_count > 1 && (
            <span> • {issue.occurrence_count} occurrences</span>
          )}
        </div>
      </div>
    </div>
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
