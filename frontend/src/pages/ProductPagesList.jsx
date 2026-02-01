/**
 * Product Pages List - Shows all monitored product pages using Polaris Web Components
 */

import { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { TitleBar } from '@shopify/app-bridge-react';
import { Loading, EmptyState, StatusBadge } from '../components';
import { useToast } from '../hooks';
import api from '../services/api';

export default function ProductPagesList() {
  const navigate = useNavigate();
  const { showSuccess, showError } = useToast();
  const [loading, setLoading] = useState(true);
  const [productPages, setProductPages] = useState([]);
  const [rescanningId, setRescanningId] = useState(null);
  const [deletingId, setDeletingId] = useState(null);

  useEffect(() => {
    loadProductPages();
  }, []);

  const loadProductPages = async () => {
    try {
      setLoading(true);
      const data = await api.getProductPages();
      setProductPages(data?.product_pages || data || []);
    } catch (error) {
      showError('Failed to load product pages');
      console.error('Load error:', error);
    } finally {
      setLoading(false);
    }
  };

  const handleRescan = async (e, id) => {
    e.stopPropagation();
    try {
      setRescanningId(id);
      await api.rescanProductPage(id);
      showSuccess('Scan queued successfully');
      loadProductPages();
    } catch (error) {
      showError('Failed to queue scan');
    } finally {
      setRescanningId(null);
    }
  };

  const handleDelete = async (e, id) => {
    e.stopPropagation();
    if (!confirm('Are you sure you want to remove this product from monitoring?')) {
      return;
    }
    try {
      setDeletingId(id);
      await api.deleteProductPage(id);
      showSuccess('Product removed from monitoring');
      setProductPages(productPages.filter(p => p.id !== id));
    } catch (error) {
      showError('Failed to remove product');
    } finally {
      setDeletingId(null);
    }
  };

  if (loading) {
    return <Loading />;
  }

  return (
    <>
      <TitleBar title="Monitored Pages">
        <button variant="primary" onClick={() => navigate('/product_pages/new')}>
          Add Products
        </button>
      </TitleBar>

      <s-section>
        {productPages.length > 0 ? (
          <s-card>
            <s-data-table>
              <s-data-table-header>
                <s-data-table-row>
                  <s-data-table-cell>Product</s-data-table-cell>
                  <s-data-table-cell>Status</s-data-table-cell>
                  <s-data-table-cell>Open Issues</s-data-table-cell>
                  <s-data-table-cell>Last Scanned</s-data-table-cell>
                  <s-data-table-cell>Actions</s-data-table-cell>
                </s-data-table-row>
              </s-data-table-header>
              <s-data-table-body>
                {productPages.map((page) => (
                  <s-data-table-row
                    key={page.id}
                    className="clickable-row"
                    onClick={() => navigate(`/product_pages/${page.id}`)}
                  >
                    <s-data-table-cell>
                      <s-block-stack gap="100">
                        <s-text variant="bodyMd" fontWeight="semibold">{page.title}</s-text>
                        <s-text variant="bodySm" tone="subdued">{page.handle}</s-text>
                      </s-block-stack>
                    </s-data-table-cell>
                    <s-data-table-cell>
                      <StatusBadge status={page.status} />
                    </s-data-table-cell>
                    <s-data-table-cell>{page.open_issues_count || 0}</s-data-table-cell>
                    <s-data-table-cell>{formatTimeAgo(page.last_scanned_at)}</s-data-table-cell>
                    <s-data-table-cell onClick={(e) => e.stopPropagation()}>
                      <s-inline-stack gap="200">
                        <s-button
                          size="slim"
                          onClick={(e) => handleRescan(e, page.id)}
                          disabled={rescanningId === page.id}
                        >
                          {rescanningId === page.id ? 'Scanning...' : 'Rescan'}
                        </s-button>
                        <s-button
                          size="slim"
                          tone="critical"
                          variant="plain"
                          onClick={(e) => handleDelete(e, page.id)}
                          disabled={deletingId === page.id}
                        >
                          Remove
                        </s-button>
                      </s-inline-stack>
                    </s-data-table-cell>
                  </s-data-table-row>
                ))}
              </s-data-table-body>
            </s-data-table>
          </s-card>
        ) : (
          <EmptyState
            title="No monitored pages"
            description="Add product pages to start monitoring their health."
            actionLabel="Add Products"
            action={() => navigate('/product_pages/new')}
          />
        )}
      </s-section>
    </>
  );
}

function formatTimeAgo(dateString) {
  if (!dateString) return 'Never';

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
