/**
 * Scan Detail Page - Shows full details of a scan
 */

import { useState, useEffect } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { TitleBar } from '@shopify/app-bridge-react';
import { Loading, StatusBadge, EmptyState, IssueItem, StatCard } from '../components';
import { useToast } from '../hooks';
import api from '../services/api';

export default function ScanShow() {
  const { id } = useParams();
  const navigate = useNavigate();
  const { showError } = useToast();
  const [loading, setLoading] = useState(true);
  const [scan, setScan] = useState(null);

  useEffect(() => {
    loadScan();
  }, [id]);

  const loadScan = async () => {
    try {
      setLoading(true);
      const data = await api.getScan(id);
      setScan(data);
    } catch (error) {
      showError('Failed to load scan');
      console.error('Load error:', error);
    } finally {
      setLoading(false);
    }
  };

  if (loading) {
    return <Loading />;
  }

  if (!scan) {
    return (
      <EmptyState
        icon="search"
        title="Scan not found"
        description="This scan may have been removed."
        actionLabel="Back to Scans"
        action={() => navigate('/scans')}
      />
    );
  }

  const issues = scan.issues || [];
  const jsErrors = scan.js_errors || [];
  const networkErrors = scan.network_errors || [];
  const consoleLogs = scan.console_logs || [];

  // Calculate duration
  let duration = null;
  if (scan.started_at && scan.completed_at) {
    const start = new Date(scan.started_at);
    const end = new Date(scan.completed_at);
    duration = Math.round((end - start) / 1000);
  }

  // Determine page load time status
  const getLoadTimeTone = () => {
    if (!scan.page_load_time_ms) return undefined;
    if (scan.page_load_time_ms > 5000) return 'critical';
    if (scan.page_load_time_ms > 3000) return 'warning';
    return 'success';
  };

  return (
    <>
      <TitleBar title="Scan Details" />

      <s-section>
        <s-card>
          <s-box padding="400">
            <s-inline-stack align="space-between" block-align="center">
              <s-block-stack gap="100">
                <s-text variant="headingMd">
                  Scan of {scan.product_page?.title || 'Unknown Product'}
                </s-text>
                <s-text variant="bodySm" tone="subdued">
                  Completed {formatDate(scan.completed_at || scan.created_at)}
                  {duration && ` • Duration: ${duration}s`}
                </s-text>
              </s-block-stack>
              <StatusBadge status={scan.status} />
            </s-inline-stack>
          </s-box>
        </s-card>
      </s-section>

      <s-section>
        <div className="card-grid">
          <StatCard
            label="Status"
            value={<StatusBadge status={scan.status} />}
          />
          <StatCard
            label="Page Load Time"
            value={scan.page_load_time_ms ? `${scan.page_load_time_ms}ms` : 'N/A'}
            tone={getLoadTimeTone()}
          />
          <StatCard
            label="Issues Found"
            value={issues.length}
            tone={issues.length > 0 ? 'critical' : 'success'}
          />
          <StatCard
            label="JS Errors"
            value={jsErrors.length}
            tone={jsErrors.length > 0 ? 'critical' : 'success'}
          />
        </div>
      </s-section>

      {scan.error_message && (
        <s-section>
          <s-banner tone="critical" title="Scan Error">
            <s-text>{scan.error_message}</s-text>
          </s-banner>
        </s-section>
      )}

      {issues.length > 0 && (
        <s-section>
          <s-block-stack gap="300">
            <s-text variant="headingMd">Issues Detected</s-text>
            <s-card>
              <s-resource-list>
                {issues.map((issue) => (
                  <IssueItem key={issue.id} issue={issue} />
                ))}
              </s-resource-list>
            </s-card>
          </s-block-stack>
        </s-section>
      )}

      {jsErrors.length > 0 && (
        <s-section>
          <s-block-stack gap="300">
            <s-text variant="headingMd">JavaScript Errors ({jsErrors.length})</s-text>
            <s-card>
              <s-box padding="400">
                <s-block-stack gap="300">
                  {jsErrors.map((error, index) => (
                    <s-box key={index} padding="300" background="bg-surface-critical">
                      <s-block-stack gap="100">
                        <s-text variant="bodyMd" fontWeight="semibold" tone="critical">
                          {error.message || error}
                        </s-text>
                        {error.url && (
                          <s-text variant="bodySm" tone="subdued">
                            {error.url}
                            {error.line && `:${error.line}`}
                            {error.column && `:${error.column}`}
                          </s-text>
                        )}
                      </s-block-stack>
                    </s-box>
                  ))}
                </s-block-stack>
              </s-box>
            </s-card>
          </s-block-stack>
        </s-section>
      )}

      {networkErrors.length > 0 && (
        <s-section>
          <s-block-stack gap="300">
            <s-text variant="headingMd">Network Errors ({networkErrors.length})</s-text>
            <s-card>
              <s-box padding="400">
                <s-block-stack gap="300">
                  {networkErrors.map((error, index) => (
                    <s-box key={index} padding="300" background="bg-surface-warning">
                      <s-block-stack gap="100">
                        <s-text variant="bodyMd" fontWeight="semibold">
                          {error.url || error}
                        </s-text>
                        {error.failure && (
                          <s-text variant="bodySm" tone="subdued">
                            {error.failure}
                          </s-text>
                        )}
                      </s-block-stack>
                    </s-box>
                  ))}
                </s-block-stack>
              </s-box>
            </s-card>
          </s-block-stack>
        </s-section>
      )}

      {consoleLogs.length > 0 && (
        <s-section>
          <s-block-stack gap="300">
            <s-text variant="headingMd">Console Logs ({consoleLogs.length})</s-text>
            <s-card>
              <s-box padding="400">
                <s-scrollable className="console-logs-scroll">
                  <s-block-stack gap="100">
                    {consoleLogs.map((log, index) => (
                      <s-inline-stack key={index} gap="200" wrap={false}>
                        <s-badge
                          tone={
                            log.type === 'error' ? 'critical' :
                            log.type === 'warning' ? 'warning' : 'info'
                          }
                          size="small"
                        >
                          {log.type || 'log'}
                        </s-badge>
                        <s-text variant="bodySm">{log.text || log}</s-text>
                      </s-inline-stack>
                    ))}
                  </s-block-stack>
                </s-scrollable>
              </s-box>
            </s-card>
          </s-block-stack>
        </s-section>
      )}

      {scan.screenshot_url && (
        <s-section>
          <s-block-stack gap="300">
            <s-text variant="headingMd">Screenshot</s-text>
            <s-card>
              <s-box padding="400">
                <s-thumbnail
                  source={scan.screenshot_url}
                  alt="Page screenshot"
                  size="large"
                />
              </s-box>
            </s-card>
          </s-block-stack>
        </s-section>
      )}

      <s-section>
        <s-button-group>
          <s-button onClick={() => navigate('/scans')}>
            Back to Scans
          </s-button>
          {scan.product_page && (
            <s-button
              variant="plain"
              onClick={() => navigate(`/product_pages/${scan.product_page.id}`)}
            >
              View Product Page
            </s-button>
          )}
        </s-button-group>
      </s-section>
    </>
  );
}

function formatDate(dateString) {
  if (!dateString) return 'N/A';
  const date = new Date(dateString);
  return date.toLocaleString();
}
