/**
 * Scan Detail Page - Shows full details of a scan
 */

import { useState, useEffect } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { TitleBar } from '@shopify/app-bridge-react';
import { Loading, StatusBadge, EmptyState, IssueItem } from '../components';
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
        icon="❌"
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

  return (
    <>
      <TitleBar title="Scan Details" />

      <s-section>
        <div className="detail-header">
          <div className="detail-header__info">
            <h1 className="detail-header__title">
              Scan of {scan.product_page?.title || 'Unknown Product'}
            </h1>
            <div className="detail-header__meta">
              Completed {formatDate(scan.completed_at || scan.created_at)}
              {duration && ` • Duration: ${duration}s`}
            </div>
          </div>
          <StatusBadge status={scan.status} />
        </div>
      </s-section>

      <s-section>
        <div className="card-grid">
          <div className="stat-card">
            <div className="stat-card__label">Status</div>
            <div className="stat-card__value">
              <StatusBadge status={scan.status} />
            </div>
          </div>
          <div className="stat-card">
            <div className="stat-card__label">Page Load Time</div>
            <div className={`stat-card__value ${
              scan.page_load_time_ms > 5000 ? 'stat-card__value--critical' :
              scan.page_load_time_ms > 3000 ? 'stat-card__value--warning' :
              'stat-card__value--success'
            }`}>
              {scan.page_load_time_ms ? `${scan.page_load_time_ms}ms` : 'N/A'}
            </div>
          </div>
          <div className="stat-card">
            <div className="stat-card__label">Issues Found</div>
            <div className={`stat-card__value ${issues.length > 0 ? 'stat-card__value--critical' : 'stat-card__value--success'}`}>
              {issues.length}
            </div>
          </div>
          <div className="stat-card">
            <div className="stat-card__label">JS Errors</div>
            <div className={`stat-card__value ${jsErrors.length > 0 ? 'stat-card__value--critical' : 'stat-card__value--success'}`}>
              {jsErrors.length}
            </div>
          </div>
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
          <div className="section">
            <h2 className="section__title">Issues Detected</h2>
            <div className="detail-card" style={{ padding: 0, overflow: 'hidden', marginTop: '12px' }}>
              <div className="issue-list">
                {issues.map((issue) => (
                  <IssueItem key={issue.id} issue={issue} />
                ))}
              </div>
            </div>
          </div>
        </s-section>
      )}

      {jsErrors.length > 0 && (
        <s-section>
          <div className="section">
            <h2 className="section__title">JavaScript Errors ({jsErrors.length})</h2>
            <div className="detail-card" style={{ marginTop: '12px' }}>
              {jsErrors.map((error, index) => (
                <div
                  key={index}
                  style={{
                    padding: '12px',
                    background: '#fce9e8',
                    borderRadius: '4px',
                    marginBottom: index < jsErrors.length - 1 ? '8px' : 0,
                    fontFamily: 'monospace',
                    fontSize: '13px'
                  }}
                >
                  <div style={{ color: '#d72c0d', fontWeight: 500 }}>
                    {error.message || error}
                  </div>
                  {error.url && (
                    <div style={{ color: '#6d7175', fontSize: '11px', marginTop: '4px' }}>
                      {error.url}
                      {error.line && `:${error.line}`}
                      {error.column && `:${error.column}`}
                    </div>
                  )}
                </div>
              ))}
            </div>
          </div>
        </s-section>
      )}

      {networkErrors.length > 0 && (
        <s-section>
          <div className="section">
            <h2 className="section__title">Network Errors ({networkErrors.length})</h2>
            <div className="detail-card" style={{ marginTop: '12px' }}>
              {networkErrors.map((error, index) => (
                <div
                  key={index}
                  style={{
                    padding: '12px',
                    background: '#fef3cd',
                    borderRadius: '4px',
                    marginBottom: index < networkErrors.length - 1 ? '8px' : 0,
                    fontFamily: 'monospace',
                    fontSize: '13px'
                  }}
                >
                  <div style={{ fontWeight: 500 }}>
                    {error.url || error}
                  </div>
                  {error.failure && (
                    <div style={{ color: '#6d7175', fontSize: '11px', marginTop: '4px' }}>
                      {error.failure}
                    </div>
                  )}
                </div>
              ))}
            </div>
          </div>
        </s-section>
      )}

      {consoleLogs.length > 0 && (
        <s-section>
          <div className="section">
            <h2 className="section__title">Console Logs ({consoleLogs.length})</h2>
            <div className="detail-card" style={{ marginTop: '12px' }}>
              <div className="technical-details" style={{ maxHeight: '300px', overflow: 'auto' }}>
                {consoleLogs.map((log, index) => (
                  <div key={index} style={{ marginBottom: '4px' }}>
                    <span style={{
                      color: log.type === 'error' ? '#d72c0d' :
                             log.type === 'warning' ? '#b98900' : '#6d7175'
                    }}>
                      [{log.type || 'log'}]
                    </span>{' '}
                    {log.text || log}
                  </div>
                ))}
              </div>
            </div>
          </div>
        </s-section>
      )}

      {scan.screenshot_url && (
        <s-section>
          <div className="section">
            <h2 className="section__title">Screenshot</h2>
            <div className="detail-card" style={{ marginTop: '12px', textAlign: 'center' }}>
              <img
                src={scan.screenshot_url}
                alt="Page screenshot"
                style={{
                  maxWidth: '100%',
                  maxHeight: '600px',
                  border: '1px solid #e1e3e5',
                  borderRadius: '4px'
                }}
              />
            </div>
          </div>
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
