/**
 * Scans List Page - Shows scan history
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
          <table className="data-table">
            <thead>
              <tr>
                <th>Product</th>
                <th>Status</th>
                <th>Load Time</th>
                <th>Issues</th>
                <th>JS Errors</th>
                <th>Date</th>
              </tr>
            </thead>
            <tbody>
              {scans.map((scan) => (
                <tr
                  key={scan.id}
                  className="clickable-row"
                  onClick={() => navigate(`/scans/${scan.id}`)}
                >
                  <td>
                    <div>
                      <strong>{scan.product_page?.title || 'Unknown'}</strong>
                      {scan.product_page?.handle && (
                        <div style={{ fontSize: '12px', color: '#6d7175' }}>
                          {scan.product_page.handle}
                        </div>
                      )}
                    </div>
                  </td>
                  <td>
                    <StatusBadge status={scan.status} />
                  </td>
                  <td>
                    {scan.page_load_time_ms ? (
                      <span style={{
                        color: scan.page_load_time_ms > 5000 ? '#d72c0d' :
                               scan.page_load_time_ms > 3000 ? '#b98900' : '#008060'
                      }}>
                        {scan.page_load_time_ms}ms
                      </span>
                    ) : (
                      'N/A'
                    )}
                  </td>
                  <td>
                    {scan.issues_count > 0 ? (
                      <span style={{ color: '#d72c0d', fontWeight: 500 }}>
                        {scan.issues_count}
                      </span>
                    ) : (
                      <span style={{ color: '#008060' }}>0</span>
                    )}
                  </td>
                  <td>
                    {(scan.js_errors?.length || 0) > 0 ? (
                      <span style={{ color: '#d72c0d' }}>
                        {scan.js_errors.length}
                      </span>
                    ) : (
                      <span style={{ color: '#008060' }}>0</span>
                    )}
                  </td>
                  <td>{formatDate(scan.completed_at || scan.created_at)}</td>
                </tr>
              ))}
            </tbody>
          </table>
        ) : (
          <EmptyState
            icon="🔍"
            title="No scans yet"
            description="Scans will appear here once you add product pages for monitoring."
            actionLabel="Add Products"
            action={() => navigate('/product_pages/new')}
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
            <span style={{ alignSelf: 'center', color: '#6d7175' }}>
              Page {page}
            </span>
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

function formatDate(dateString) {
  if (!dateString) return 'N/A';
  const date = new Date(dateString);
  return date.toLocaleString();
}
