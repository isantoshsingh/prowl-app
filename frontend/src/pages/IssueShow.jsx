/**
 * Issue Detail Page - Shows full details of an issue using Polaris Web Components
 */

import { useState, useEffect } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { TitleBar } from '@shopify/app-bridge-react';
import { Loading, StatusBadge, EmptyState, StatCard } from '../components';
import { useToast } from '../hooks';
import api from '../services/api';

// Issue type recommendations
const RECOMMENDATIONS = {
  missing_add_to_cart: {
    title: 'Add to Cart Button Missing or Broken',
    steps: [
      'Check your theme\'s product template for the add-to-cart form',
      'Verify the form action points to /cart/add',
      'Ensure JavaScript is not throwing errors that prevent button rendering',
      'Test the product page in an incognito window',
      'Check if the product is available for sale and has inventory'
    ]
  },
  variant_selector_error: {
    title: 'Variant Selector Issue',
    steps: [
      'Review your theme\'s variant selector JavaScript',
      'Check for conflicting apps that modify variant behavior',
      'Verify all variant options are properly configured',
      'Test selecting different variants and check browser console for errors',
      'Ensure variant images are properly linked'
    ]
  },
  js_error: {
    title: 'JavaScript Error Detected',
    steps: [
      'Open browser developer tools and check the Console tab',
      'Identify the source of the error (theme, app, or custom code)',
      'If from an app, try disabling it temporarily to confirm',
      'Review recent changes to your theme or installed apps',
      'Contact the app developer or theme support if needed'
    ]
  },
  liquid_error: {
    title: 'Liquid Template Error',
    steps: [
      'Look for "Liquid error" text visible on the page',
      'Check your theme editor for template syntax errors',
      'Verify referenced objects and variables exist',
      'Review recent theme customizations',
      'Check if product metafields are properly configured'
    ]
  },
  missing_images: {
    title: 'Product Images Not Loading',
    steps: [
      'Verify images are uploaded in Shopify admin',
      'Check if images have proper file extensions',
      'Test images in different browsers',
      'Look for CDN or hosting issues',
      'Ensure lazy loading is configured correctly'
    ]
  },
  missing_price: {
    title: 'Price Not Displayed',
    steps: [
      'Check your theme\'s product template for price elements',
      'Verify the product has a price set in Shopify admin',
      'Look for CSS that might be hiding the price',
      'Check if price depends on variant selection',
      'Review theme customization settings for price display'
    ]
  },
  slow_page_load: {
    title: 'Slow Page Load Time',
    steps: [
      'Optimize and compress product images',
      'Review installed apps for performance impact',
      'Minimize custom JavaScript and CSS',
      'Consider lazy loading for below-the-fold content',
      'Use browser caching effectively',
      'Review third-party scripts and tracking codes'
    ]
  }
};

export default function IssueShow() {
  const { id } = useParams();
  const navigate = useNavigate();
  const { showSuccess, showError } = useToast();
  const [loading, setLoading] = useState(true);
  const [issue, setIssue] = useState(null);
  const [acknowledging, setAcknowledging] = useState(false);

  useEffect(() => {
    loadIssue();
  }, [id]);

  const loadIssue = async () => {
    try {
      setLoading(true);
      const data = await api.getIssue(id);
      setIssue(data);
    } catch (error) {
      showError('Failed to load issue');
      console.error('Load error:', error);
    } finally {
      setLoading(false);
    }
  };

  const handleAcknowledge = async () => {
    try {
      setAcknowledging(true);
      await api.acknowledgeIssue(id);
      showSuccess('Issue acknowledged');
      loadIssue();
    } catch (error) {
      showError('Failed to acknowledge issue');
    } finally {
      setAcknowledging(false);
    }
  };

  if (loading) {
    return <Loading />;
  }

  if (!issue) {
    return (
      <EmptyState
        title="Issue not found"
        description="This issue may have been resolved or removed."
        actionLabel="Back to Issues"
        action={() => navigate('/issues')}
      />
    );
  }

  const recommendation = RECOMMENDATIONS[issue.issue_type] || null;

  return (
    <>
      <TitleBar title="Issue Details">
        {issue.status === 'open' && (
          <button
            onClick={handleAcknowledge}
            disabled={acknowledging}
          >
            {acknowledging ? 'Acknowledging...' : 'Acknowledge'}
          </button>
        )}
      </TitleBar>

      <s-section>
        <s-inline-stack align="space-between" block-align="start">
          <s-block-stack gap="200">
            <s-text variant="headingLg">{issue.title}</s-text>
            <s-inline-stack gap="200" block-align="center">
              <div className={`severity-dot severity-dot--${issue.severity === 'high' ? 'critical' : issue.severity === 'medium' ? 'warning' : 'info'}`} />
              <s-text tone="subdued">{issue.severity?.toUpperCase()} severity</s-text>
              {issue.product_page && (
                <>
                  <s-text tone="subdued">•</s-text>
                  <s-button variant="plain" onClick={() => navigate(`/product_pages/${issue.product_page.id}`)}>
                    {issue.product_page.title}
                  </s-button>
                </>
              )}
            </s-inline-stack>
          </s-block-stack>
          <StatusBadge status={issue.status} />
        </s-inline-stack>
      </s-section>

      <s-section>
        <div className="card-grid">
          <StatCard label="Status" value={<StatusBadge status={issue.status} />} />
          <StatCard label="Occurrences" value={issue.occurrence_count || 1} />
          <StatCard label="First Detected" value={formatDate(issue.first_detected_at)} />
          <StatCard label="Last Detected" value={formatDate(issue.last_detected_at)} />
        </div>
      </s-section>

      <s-section>
        <s-card>
          <s-box padding="400">
            <s-block-stack gap="300">
              <s-text variant="headingMd">Description</s-text>
              <s-text>{issue.description || 'No description available.'}</s-text>
            </s-block-stack>
          </s-box>
        </s-card>
      </s-section>

      {recommendation && (
        <s-section>
          <s-card>
            <s-box padding="400">
              <s-block-stack gap="300">
                <s-text variant="headingMd">Recommended Actions</s-text>
                <s-text tone="subdued">{recommendation.title}</s-text>
                <s-list>
                  {recommendation.steps.map((step, index) => (
                    <s-list-item key={index}>{step}</s-list-item>
                  ))}
                </s-list>
              </s-block-stack>
            </s-box>
          </s-card>
        </s-section>
      )}

      {issue.evidence && Object.keys(issue.evidence).length > 0 && (
        <s-section>
          <s-card>
            <s-box padding="400">
              <s-block-stack gap="300">
                <s-text variant="headingMd">Technical Details</s-text>
                <div className="technical-details">
                  {JSON.stringify(issue.evidence, null, 2)}
                </div>
              </s-block-stack>
            </s-box>
          </s-card>
        </s-section>
      )}

      {issue.acknowledged_at && (
        <s-section>
          <s-card>
            <s-box padding="400">
              <s-block-stack gap="200">
                <s-text variant="headingMd">Acknowledgement</s-text>
                <s-text>
                  Acknowledged on {formatDate(issue.acknowledged_at)}
                  {issue.acknowledged_by && ` by ${issue.acknowledged_by}`}
                </s-text>
              </s-block-stack>
            </s-box>
          </s-card>
        </s-section>
      )}

      <s-section>
        <s-inline-stack gap="300">
          <s-button onClick={() => navigate('/issues')}>
            Back to Issues
          </s-button>
          {issue.product_page && (
            <s-button
              variant="plain"
              onClick={() => navigate(`/product_pages/${issue.product_page.id}`)}
            >
              View Product Page
            </s-button>
          )}
        </s-inline-stack>
      </s-section>
    </>
  );
}

function formatDate(dateString) {
  if (!dateString) return 'N/A';
  const date = new Date(dateString);
  return date.toLocaleString();
}
