/**
 * Dashboard Page - Main overview of PDP health using Polaris Web Components
 */

import { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { StatCard, IssueItem, Loading, EmptyState, BillingBanner, StatusBadge } from '../components';
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
      </s-section>

      <s-section>
        <s-text variant="headingMd">Health Overview</s-text>
        <s-box padding-block-start="400">
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
        </s-box>
      </s-section>

      <s-section>
        <s-inline-stack align="space-between" block-align="center">
          <s-text variant="headingMd">Open Issues</s-text>
          <s-button variant="plain" onClick={() => navigate('/issues')}>
            View all
          </s-button>
        </s-inline-stack>
        <s-box padding-block-start="400">
          {openIssues.length > 0 ? (
            <s-card>
              <s-resource-list>
                {openIssues.map((issue) => (
                  <IssueItem key={issue.id} issue={issue} />
                ))}
              </s-resource-list>
            </s-card>
          ) : (
            <EmptyState
              title="No open issues"
              description="All your product pages are healthy."
            />
          )}
        </s-box>
      </s-section>

      <s-section>
        <s-inline-stack align="space-between" block-align="center">
          <s-text variant="headingMd">Recent Scans</s-text>
          <s-button variant="plain" onClick={() => navigate('/scans')}>
            View all
          </s-button>
        </s-inline-stack>
        <s-box padding-block-start="400">
          {recentScans.length > 0 ? (
            <s-card>
              <s-data-table>
                <s-data-table-header>
                  <s-data-table-row>
                    <s-data-table-cell>Product</s-data-table-cell>
                    <s-data-table-cell>Status</s-data-table-cell>
                    <s-data-table-cell>Issues</s-data-table-cell>
                    <s-data-table-cell>Time</s-data-table-cell>
                  </s-data-table-row>
                </s-data-table-header>
                <s-data-table-body>
                  {recentScans.map((scan) => (
                    <s-data-table-row
                      key={scan.id}
                      className="clickable-row"
                      onClick={() => navigate(`/scans/${scan.id}`)}
                    >
                      <s-data-table-cell>{scan.product_page?.title || 'Unknown'}</s-data-table-cell>
                      <s-data-table-cell>
                        <StatusBadge status={scan.status} />
                      </s-data-table-cell>
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
              description="Add product pages to start monitoring."
              actionLabel="Add Products"
              action={() => navigate('/product_pages/new')}
            />
          )}
        </s-box>
      </s-section>
    </>
  );
}

function formatDate(dateString) {
  if (!dateString) return 'N/A';
  const date = new Date(dateString);
  return date.toLocaleString();
}
