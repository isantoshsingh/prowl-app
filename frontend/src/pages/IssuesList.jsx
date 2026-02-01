/**
 * Issues List Page - Shows all detected issues with filtering using Polaris Web Components
 */

import { useState, useEffect } from 'react';
import { useNavigate, useSearchParams } from 'react-router-dom';
import { TitleBar } from '@shopify/app-bridge-react';
import { Loading, EmptyState, StatusBadge } from '../components';
import { useToast } from '../hooks';
import api from '../services/api';

const STATUS_OPTIONS = [
  { value: '', label: 'All statuses' },
  { value: 'open', label: 'Open' },
  { value: 'acknowledged', label: 'Acknowledged' },
  { value: 'resolved', label: 'Resolved' }
];

const SEVERITY_OPTIONS = [
  { value: '', label: 'All severities' },
  { value: 'high', label: 'High' },
  { value: 'medium', label: 'Medium' },
  { value: 'low', label: 'Low' }
];

export default function IssuesList() {
  const navigate = useNavigate();
  const [searchParams, setSearchParams] = useSearchParams();
  const { showError } = useToast();

  const [loading, setLoading] = useState(true);
  const [issues, setIssues] = useState([]);
  const [statusFilter, setStatusFilter] = useState(searchParams.get('status') || '');
  const [severityFilter, setSeverityFilter] = useState(searchParams.get('severity') || '');
  const [page, setPage] = useState(1);
  const [hasMore, setHasMore] = useState(false);

  useEffect(() => {
    loadIssues();
  }, [statusFilter, severityFilter, page]);

  const loadIssues = async () => {
    try {
      setLoading(true);
      const params = { page };
      if (statusFilter) params.status = statusFilter;
      if (severityFilter) params.severity = severityFilter;

      const data = await api.getIssues(params);
      const issuesList = data?.issues || data || [];
      setIssues(issuesList);
      setHasMore(data?.has_more || false);

      const newParams = new URLSearchParams();
      if (statusFilter) newParams.set('status', statusFilter);
      if (severityFilter) newParams.set('severity', severityFilter);
      setSearchParams(newParams);
    } catch (error) {
      showError('Failed to load issues');
      console.error('Load error:', error);
    } finally {
      setLoading(false);
    }
  };

  const handleStatusChange = (e) => {
    setStatusFilter(e.target.value);
    setPage(1);
  };

  const handleSeverityChange = (e) => {
    setSeverityFilter(e.target.value);
    setPage(1);
  };

  const clearFilters = () => {
    setStatusFilter('');
    setSeverityFilter('');
    setPage(1);
  };

  if (loading && issues.length === 0) {
    return <Loading />;
  }

  const hasFilters = statusFilter || severityFilter;

  return (
    <>
      <TitleBar title="Issues" />

      <s-section>
        <s-inline-stack gap="400" block-align="center">
          <s-select
            label="Status"
            labelHidden
            value={statusFilter}
            onChange={handleStatusChange}
          >
            {STATUS_OPTIONS.map(opt => (
              <option key={opt.value} value={opt.value}>{opt.label}</option>
            ))}
          </s-select>
          <s-select
            label="Severity"
            labelHidden
            value={severityFilter}
            onChange={handleSeverityChange}
          >
            {SEVERITY_OPTIONS.map(opt => (
              <option key={opt.value} value={opt.value}>{opt.label}</option>
            ))}
          </s-select>
          {hasFilters && (
            <s-button variant="plain" onClick={clearFilters}>
              Clear filters
            </s-button>
          )}
        </s-inline-stack>
      </s-section>

      <s-section>
        {issues.length > 0 ? (
          <s-card>
            <s-data-table>
              <s-data-table-header>
                <s-data-table-row>
                  <s-data-table-cell>Severity</s-data-table-cell>
                  <s-data-table-cell>Issue</s-data-table-cell>
                  <s-data-table-cell>Product</s-data-table-cell>
                  <s-data-table-cell>Status</s-data-table-cell>
                  <s-data-table-cell>Occurrences</s-data-table-cell>
                  <s-data-table-cell>Last Detected</s-data-table-cell>
                </s-data-table-row>
              </s-data-table-header>
              <s-data-table-body>
                {issues.map((issue) => (
                  <s-data-table-row
                    key={issue.id}
                    className="clickable-row"
                    onClick={() => navigate(`/issues/${issue.id}`)}
                  >
                    <s-data-table-cell>
                      <div className={`severity-dot severity-dot--${issue.severity === 'high' ? 'critical' : issue.severity === 'medium' ? 'warning' : 'info'}`} />
                    </s-data-table-cell>
                    <s-data-table-cell>
                      <s-block-stack gap="100">
                        <s-text variant="bodyMd" fontWeight="semibold">{issue.title}</s-text>
                        <s-text variant="bodySm" tone="subdued">
                          {issue.issue_type?.replace(/_/g, ' ')}
                        </s-text>
                      </s-block-stack>
                    </s-data-table-cell>
                    <s-data-table-cell>{issue.product_page?.title || 'Unknown'}</s-data-table-cell>
                    <s-data-table-cell>
                      <StatusBadge status={issue.status} />
                    </s-data-table-cell>
                    <s-data-table-cell>{issue.occurrence_count || 1}</s-data-table-cell>
                    <s-data-table-cell>{formatTimeAgo(issue.last_detected_at)}</s-data-table-cell>
                  </s-data-table-row>
                ))}
              </s-data-table-body>
            </s-data-table>
          </s-card>
        ) : (
          <EmptyState
            title={hasFilters ? 'No issues match your filters' : 'No issues found'}
            description={
              hasFilters
                ? 'Try adjusting your filters to see more results.'
                : 'Great news! All your product pages are healthy.'
            }
            actionLabel={hasFilters ? 'Clear filters' : undefined}
            action={hasFilters ? clearFilters : undefined}
          />
        )}

        {(hasMore || page > 1) && (
          <s-box padding-block-start="400">
            <s-inline-stack align="space-between">
              <s-button
                disabled={page === 1}
                onClick={() => setPage(p => p - 1)}
              >
                Previous
              </s-button>
              <s-button
                disabled={!hasMore}
                onClick={() => setPage(p => p + 1)}
              >
                Next
              </s-button>
            </s-inline-stack>
          </s-box>
        )}
      </s-section>
    </>
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
