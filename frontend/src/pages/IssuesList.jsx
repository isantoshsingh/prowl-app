/**
 * Issues List Page - Shows all detected issues with filtering
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

      // Update URL params
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
        <div className="flex items-center gap-4 mb-4">
          <div className="form-group" style={{ marginBottom: 0 }}>
            <select
              value={statusFilter}
              onChange={handleStatusChange}
              style={{
                padding: '8px 12px',
                borderRadius: '4px',
                border: '1px solid #c4cdd5',
                fontSize: '14px'
              }}
            >
              {STATUS_OPTIONS.map(opt => (
                <option key={opt.value} value={opt.value}>{opt.label}</option>
              ))}
            </select>
          </div>
          <div className="form-group" style={{ marginBottom: 0 }}>
            <select
              value={severityFilter}
              onChange={handleSeverityChange}
              style={{
                padding: '8px 12px',
                borderRadius: '4px',
                border: '1px solid #c4cdd5',
                fontSize: '14px'
              }}
            >
              {SEVERITY_OPTIONS.map(opt => (
                <option key={opt.value} value={opt.value}>{opt.label}</option>
              ))}
            </select>
          </div>
          {hasFilters && (
            <s-button variant="plain" onClick={clearFilters}>
              Clear filters
            </s-button>
          )}
        </div>

        {issues.length > 0 ? (
          <table className="data-table">
            <thead>
              <tr>
                <th>Severity</th>
                <th>Issue</th>
                <th>Product</th>
                <th>Status</th>
                <th>Occurrences</th>
                <th>Last Detected</th>
              </tr>
            </thead>
            <tbody>
              {issues.map((issue) => (
                <tr
                  key={issue.id}
                  className="clickable-row"
                  onClick={() => navigate(`/issues/${issue.id}`)}
                >
                  <td>
                    <span className={`issue-item__severity issue-item__severity--${issue.severity}`}
                      style={{ display: 'inline-block', width: 10, height: 10, borderRadius: '50%' }}
                    />
                  </td>
                  <td>
                    <div>
                      <strong>{issue.title}</strong>
                      <div style={{ fontSize: '12px', color: '#6d7175' }}>
                        {issue.issue_type?.replace(/_/g, ' ')}
                      </div>
                    </div>
                  </td>
                  <td>{issue.product_page?.title || 'Unknown'}</td>
                  <td>
                    <StatusBadge status={issue.status} />
                  </td>
                  <td>{issue.occurrence_count || 1}</td>
                  <td>{formatTimeAgo(issue.last_detected_at)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        ) : (
          <EmptyState
            icon={hasFilters ? '🔍' : '✅'}
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
          <div className="flex justify-between mt-4">
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
          </div>
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
