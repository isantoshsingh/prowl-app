/**
 * Dashboard Page - Main overview of PDP health
 */

import { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { StatCard, IssueItem, Loading, EmptyState, BillingBanner } from '../components';
import { useToast } from '../hooks';
import api from '../services/api';

export default function Dashboard() {
  const navigate = useNavigate();
  const { showError } = useToast();
  const [loading, setLoading] = useState(true);
  const [stats, setStats] = useState(null);
  const [openIssues, setOpenIssues] = useState([]);
  const [recentScans, setRecentScans] = useState([]);

  useEffect(() => {
    loadDashboard();
  }, []);

  const loadDashboard = async () => {
    try {
      setLoading(true);
      const [statsData, issuesData, scansData] = await Promise.all([
        api.getDashboardStats(),
        api.getIssues({ status: 'open', limit: 5 }),
        api.getScans({ limit: 5 })
      ]);
      setStats(statsData);
      setOpenIssues(issuesData?.issues || issuesData || []);
      setRecentScans(scansData?.scans || scansData || []);
    } catch (error) {
      showError('Failed to load dashboard');
      console.error('Dashboard error:', error);
    } finally {
      setLoading(false);
    }
  };

  const handleSubscribe = async () => {
    try {
      const result = await api.createBillingCharge();
      if (result?.confirmation_url) {
        window.open(result.confirmation_url, '_top');
      }
    } catch (error) {
      showError('Failed to start subscription');
    }
  };

  if (loading) {
    return <Loading />;
  }

  return (
    <>
      <s-section>
        <BillingBanner
          billingStatus={stats?.billing_status}
          trialDaysRemaining={stats?.trial_days_remaining}
          onSubscribe={handleSubscribe}
        />

        <div className="section">
          <div className="section__header">
            <h2 className="section__title">Health Overview</h2>
          </div>
          <div className="card-grid">
            <StatCard
              label="Total Monitored Pages"
              value={stats?.total_pages || 0}
            />
            <StatCard
              label="Healthy"
              value={stats?.healthy_pages || 0}
              variant="success"
            />
            <StatCard
              label="Warning"
              value={stats?.warning_pages || 0}
              variant="warning"
            />
            <StatCard
              label="Critical"
              value={stats?.critical_pages || 0}
              variant="critical"
            />
          </div>
        </div>
      </s-section>

      <s-section>
        <div className="section">
          <div className="section__header">
            <h2 className="section__title">Open Issues</h2>
            <s-button variant="plain" onClick={() => navigate('/issues')}>
              View all
            </s-button>
          </div>
          {openIssues.length > 0 ? (
            <div className="detail-card" style={{ padding: 0, overflow: 'hidden' }}>
              <div className="issue-list">
                {openIssues.map((issue) => (
                  <IssueItem key={issue.id} issue={issue} />
                ))}
              </div>
            </div>
          ) : (
            <EmptyState
              icon="✅"
              title="No open issues"
              description="All your product pages are healthy."
            />
          )}
        </div>
      </s-section>

      <s-section>
        <div className="section">
          <div className="section__header">
            <h2 className="section__title">Recent Scans</h2>
            <s-button variant="plain" onClick={() => navigate('/scans')}>
              View all
            </s-button>
          </div>
          {recentScans.length > 0 ? (
            <table className="data-table">
              <thead>
                <tr>
                  <th>Product</th>
                  <th>Status</th>
                  <th>Issues</th>
                  <th>Time</th>
                </tr>
              </thead>
              <tbody>
                {recentScans.map((scan) => (
                  <tr
                    key={scan.id}
                    className="clickable-row"
                    onClick={() => navigate(`/scans/${scan.id}`)}
                  >
                    <td>{scan.product_page?.title || 'Unknown'}</td>
                    <td>
                      <span className={`status-badge status-badge--${scan.status}`}>
                        {scan.status}
                      </span>
                    </td>
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
              description="Add product pages to start monitoring."
              actionLabel="Add Products"
              action={() => navigate('/product_pages/new')}
            />
          )}
        </div>
      </s-section>
    </>
  );
}

function formatDate(dateString) {
  if (!dateString) return 'N/A';
  const date = new Date(dateString);
  return date.toLocaleString();
}
