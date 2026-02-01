/**
 * Scans List Page - Shows scan history using Polaris Web Components
 */

import { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { TitleBar } from '@shopify/app-bridge-react';
import { Loading, EmptyState, StatusBadge } from '../components';
import { useToast } from '../hooks';
import api from '../services/api';

export default function ScansList() {
  const navigate = useNavigate();
  const { showError } = useToast();
  const [loading, setLoading] = useState(true);
  const [scans, setScans] = useState([]);
  const [page, setPage] = useState(1);
  const [hasMore, setHasMore] = useState(false);

  useEffect(() => {
    loadScans();
  }, [page]);

  const loadScans = async () => {
    try {
      setLoading(true);
      const data = await api.getScans({ page });
      const scansList = data?.scans || data || [];
      setScans(scansList);
      setHasMore(data?.has_more || false);
    } catch (error) {
      showError('Failed to load scans');
      console.error('Load error:', error);
    } finally {
      setLoading(false);
    }
  };

  if (loading && scans.length === 0) {
    return <Loading />;
  }

  return (
    <>
      <TitleBar title="Scan History" />

      <s-section>
        {scans.length > 0 ? (
          <s-card>
            <s-data-table>
              <s-data-table-header>
                <s-data-table-row>
                  <s-data-table-cell>Product</s-data-table-cell>
                  <s-data-table-cell>Status</s-data-table-cell>
                  <s-data-table-cell>Load Time</s-data-table-cell>
                  <s-data-table-cell>Issues</s-data-table-cell>
                  <s-data-table-cell>JS Errors</s-data-table-cell>
                  <s-data-table-cell>Date</s-data-table-cell>
                </s-data-table-row>
              </s-data-table-header>
              <s-data-table-body>
                {scans.map((scan) => (
                  <s-data-table-row
                    key={scan.id}
                    className="clickable-row"
                    onClick={() => navigate(`/scans/${scan.id}`)}
                  >
                    <s-data-table-cell>
                      <s-block-stack gap="100">
                        <s-text variant="bodyMd" fontWeight="semibold">{scan.product_page?.title || 'Unknown'}</s-text>
                        {scan.product_page?.handle && (
                          <s-text variant="bodySm" tone="subdued">{scan.product_page.handle}</s-text>
                        )}
                      </s-block-stack>
                    </s-data-table-cell>
                    <s-data-table-cell>
                      <StatusBadge status={scan.status} />
                    </s-data-table-cell>
                    <s-data-table-cell>
                      {scan.page_load_time_ms ? (
                        <s-text tone={scan.page_load_time_ms > 5000 ? 'critical' : scan.page_load_time_ms > 3000 ? 'warning' : 'success'}>
                          {scan.page_load_time_ms}ms
                        </s-text>
                      ) : (
                        'N/A'
                      )}
                    </s-data-table-cell>
                    <s-data-table-cell>
                      <s-text tone={scan.issues_count > 0 ? 'critical' : 'success'} fontWeight={scan.issues_count > 0 ? 'semibold' : undefined}>
                        {scan.issues_count || 0}
                      </s-text>
                    </s-data-table-cell>
                    <s-data-table-cell>
                      <s-text tone={(scan.js_errors?.length || 0) > 0 ? 'critical' : 'success'}>
                        {scan.js_errors?.length || 0}
                      </s-text>
                    </s-data-table-cell>
                    <s-data-table-cell>{formatDate(scan.completed_at || scan.created_at)}</s-data-table-cell>
                  </s-data-table-row>
                ))}
              </s-data-table-body>
            </s-data-table>
          </s-card>
        ) : (
          <EmptyState
            title="No scans yet"
            description="Scans will appear here once you add product pages for monitoring."
            actionLabel="Add Products"
            action={() => navigate('/product_pages/new')}
          />
        )}

        {(hasMore || page > 1) && (
          <s-box padding-block-start="400">
            <s-inline-stack align="space-between" block-align="center">
              <s-button
                disabled={page === 1}
                onClick={() => setPage(p => p - 1)}
              >
                Previous
              </s-button>
              <s-text tone="subdued">Page {page}</s-text>
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

function formatDate(dateString) {
  if (!dateString) return 'N/A';
  const date = new Date(dateString);
  return date.toLocaleString();
}
