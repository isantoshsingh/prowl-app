/**
 * Product Page Detail - Shows details of a single monitored product
 */

import { useState, useEffect } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { TitleBar } from '@shopify/app-bridge-react';
import { Loading, StatusBadge, IssueItem, EmptyState } from '../components';
import { useToast } from '../hooks';
import api from '../services/api';

export default function ProductPageShow() {
  const { id } = useParams();
  const navigate = useNavigate();
  const { showSuccess, showError } = useToast();
  const [loading, setLoading] = useState(true);
  const [productPage, setProductPage] = useState(null);
  const [rescanning, setRescanning] = useState(false);

  useEffect(() => {
    loadProductPage();
  }, [id]);

  const loadProductPage = async () => {
    try {
      setLoading(true);
      const data = await api.getProductPage(id);
      setProductPage(data);
    } catch (error) {
      showError('Failed to load product page');
      console.error('Load error:', error);
    } finally {
      setLoading(false);
    }
  };

  const handleRescan = async () => {
    try {
      setRescanning(true);
      await api.rescanProductPage(id);
      showSuccess('Scan queued successfully');
      loadProductPage();
    } catch (error) {
      showError('Failed to queue scan');
    } finally {
      setRescanning(false);
    }
  };

  const handleDelete = async () => {
    if (!confirm('Are you sure you want to remove this product from monitoring?')) {
      return;
    }
    try {
      await api.deleteProductPage(id);
      showSuccess('Product removed from monitoring');
      navigate('/product_pages');
    } catch (error) {
      showError('Failed to remove product');
    }
  };

  if (loading) {
    return <Loading />;
  }

  if (!productPage) {
    return (
      <EmptyState
        icon="❌"
        title="Product not found"
        description="This product page may have been removed."
        actionLabel="Back to Products"
        action={() => navigate('/product_pages')}
      />
    );
  }

  const issues = productPage.issues || [];
  const recentScans = productPage.recent_scans || productPage.scans || [];

  return (
    <>
      <TitleBar title={productPage.title}>
        <button onClick={handleRescan} disabled={rescanning}>
          {rescanning ? 'Scanning...' : 'Rescan Now'}
        </button>
        <button tone="critical" onClick={handleDelete}>
          Remove
        </button>
      </TitleBar>

      <s-section>
        <div className="detail-header">
          <div className="detail-header__info">
            <h1 className="detail-header__title">{productPage.title}</h1>
            <div className="detail-header__meta">
              <span>Handle: {productPage.handle}</span>
              {productPage.last_scanned_at && (
                <span> • Last scanned: {formatDate(productPage.last_scanned_at)}</span>
              )}
            </div>
          </div>
          <StatusBadge status={productPage.status} />
        </div>
      </s-section>

      <s-section>
        <div className="card-grid">
          <div className="stat-card">
            <div className="stat-card__label">Status</div>
            <div className="stat-card__value">
              <StatusBadge status={productPage.status} />
            </div>
          </div>
          <div className="stat-card">
            <div className="stat-card__label">Open Issues</div>
            <div className={`stat-card__value ${issues.filter(i => i.status === 'open').length > 0 ? 'stat-card__value--critical' : 'stat-card__value--success'}`}>
              {issues.filter(i => i.status === 'open').length}
            </div>
          </div>
          <div className="stat-card">
            <div className="stat-card__label">Total Scans</div>
            <div className="stat-card__value">{recentScans.length}</div>
          </div>
        </div>
      </s-section>

      <s-section>
        <div className="section">
          <div className="section__header">
            <h2 className="section__title">Issues</h2>
          </div>
          {issues.length > 0 ? (
            <div className="detail-card" style={{ padding: 0, overflow: 'hidden' }}>
              <div className="issue-list">
                {issues.map((issue) => (
                  <IssueItem key={issue.id} issue={issue} />
                ))}
              </div>
            </div>
          ) : (
            <EmptyState
              icon="✅"
              title="No issues found"
              description="This product page is healthy."
            />
          )}
        </div>
      </s-section>

      <s-section>
        <div className="section">
          <div className="section__header">
            <h2 className="section__title">Recent Scans</h2>
          </div>
          {recentScans.length > 0 ? (
            <table className="data-table">
              <thead>
                <tr>
                  <th>Status</th>
                  <th>Load Time</th>
                  <th>Issues Found</th>
                  <th>Date</th>
                </tr>
              </thead>
              <tbody>
                {recentScans.slice(0, 10).map((scan) => (
                  <tr
                    key={scan.id}
                    className="clickable-row"
                    onClick={() => navigate(`/scans/${scan.id}`)}
                  >
                    <td>
                      <StatusBadge status={scan.status} />
                    </td>
                    <td>{scan.page_load_time_ms ? `${scan.page_load_time_ms}ms` : 'N/A'}</td>
                    <td>{scan.issues_count || 0}</td>
                    <td>{formatDate(scan.completed_at || scan.created_at)}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          ) : (
            <EmptyState
              icon="🔍"
              title="No scans yet"
              description="Click 'Rescan Now' to scan this product page."
            />
          )}
        </div>
      </s-section>

      {productPage.url && (
        <s-section>
          <s-button
            variant="plain"
            onClick={() => window.open(productPage.url, '_blank')}
          >
            View product page on storefront
          </s-button>
        </s-section>
      )}
    </>
  );
}

function formatDate(dateString) {
  if (!dateString) return 'N/A';
  const date = new Date(dateString);
  return date.toLocaleString();
}
