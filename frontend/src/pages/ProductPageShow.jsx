/**
 * Product Page Detail - Shows details of a single monitored product using Polaris Web Components
 */

import { useState, useEffect } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { TitleBar } from '@shopify/app-bridge-react';
import { Loading, StatusBadge, IssueItem, EmptyState, StatCard } from '../components';
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
        title="Product not found"
        description="This product page may have been removed."
        actionLabel="Back to Products"
        action={() => navigate('/product_pages')}
      />
    );
  }

  const issues = productPage.issues || [];
  const recentScans = productPage.recent_scans || productPage.scans || [];
  const openIssuesCount = issues.filter(i => i.status === 'open').length;

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
        <s-inline-stack align="space-between" block-align="start">
          <s-block-stack gap="200">
            <s-text variant="headingLg">{productPage.title}</s-text>
            <s-text variant="bodySm" tone="subdued">
              Handle: {productPage.handle}
              {productPage.last_scanned_at && ` • Last scanned: ${formatDate(productPage.last_scanned_at)}`}
            </s-text>
          </s-block-stack>
          <StatusBadge status={productPage.status} />
        </s-inline-stack>
      </s-section>

      <s-section>
        <div className="card-grid">
          <StatCard label="Status" value={<StatusBadge status={productPage.status} />} />
          <StatCard
            label="Open Issues"
            value={openIssuesCount}
            variant={openIssuesCount > 0 ? 'critical' : 'success'}
          />
          <StatCard label="Total Scans" value={recentScans.length} />
        </div>
      </s-section>

      <s-section>
        <s-text variant="headingMd">Issues</s-text>
        <s-box padding-block-start="400">
          {issues.length > 0 ? (
            <s-card>
              <s-resource-list>
                {issues.map((issue) => (
                  <IssueItem key={issue.id} issue={issue} />
                ))}
              </s-resource-list>
            </s-card>
          ) : (
            <EmptyState
              title="No issues found"
              description="This product page is healthy."
            />
          )}
        </s-box>
      </s-section>

      <s-section>
        <s-text variant="headingMd">Recent Scans</s-text>
        <s-box padding-block-start="400">
          {recentScans.length > 0 ? (
            <s-card>
              <s-data-table>
                <s-data-table-header>
                  <s-data-table-row>
                    <s-data-table-cell>Status</s-data-table-cell>
                    <s-data-table-cell>Load Time</s-data-table-cell>
                    <s-data-table-cell>Issues Found</s-data-table-cell>
                    <s-data-table-cell>Date</s-data-table-cell>
                  </s-data-table-row>
                </s-data-table-header>
                <s-data-table-body>
                  {recentScans.slice(0, 10).map((scan) => (
                    <s-data-table-row
                      key={scan.id}
                      className="clickable-row"
                      onClick={() => navigate(`/scans/${scan.id}`)}
                    >
                      <s-data-table-cell>
                        <StatusBadge status={scan.status} />
                      </s-data-table-cell>
                      <s-data-table-cell>{scan.page_load_time_ms ? `${scan.page_load_time_ms}ms` : 'N/A'}</s-data-table-cell>
                      <s-data-table-cell>{scan.issues_count || 0}</s-data-table-cell>
                      <s-data-table-cell>{formatDate(scan.completed_at || scan.created_at)}</s-data-table-cell>
                    </s-data-table-row>
                  ))}
                </s-data-table-body>
              </s-data-table>
            </s-card>
          ) : (
            <EmptyState
              title="No scans yet"
              description="Click 'Rescan Now' to scan this product page."
            />
          )}
        </s-box>
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
