/**
 * Issue Detail Page - Shows full details of an issue with recommendations
 */

import { useState, useEffect } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { TitleBar } from '@shopify/app-bridge-react';
import { Loading, StatusBadge, EmptyState } from '../components';
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
        icon="❌"
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
        <div className="detail-header">
          <div className="detail-header__info">
            <h1 className="detail-header__title">{issue.title}</h1>
            <div className="detail-header__meta">
              <span style={{ marginRight: 8 }}>
                <span
                  className={`issue-item__severity issue-item__severity--${issue.severity}`}
                  style={{ display: 'inline-block', width: 8, height: 8, borderRadius: '50%', marginRight: 4 }}
                />
                {issue.severity?.toUpperCase()} severity
              </span>
              {issue.product_page && (
                <span>
                  • <a
                    href="#"
                    onClick={(e) => {
                      e.preventDefault();
                      navigate(`/product_pages/${issue.product_page.id}`);
                    }}
                    style={{ color: '#2c6ecb' }}
                  >
                    {issue.product_page.title}
                  </a>
                </span>
              )}
            </div>
          </div>
          <StatusBadge status={issue.status} />
        </div>
      </s-section>

      <s-section>
        <div className="card-grid">
          <div className="stat-card">
            <div className="stat-card__label">Status</div>
            <div className="stat-card__value">
              <StatusBadge status={issue.status} />
            </div>
          </div>
          <div className="stat-card">
            <div className="stat-card__label">Occurrences</div>
            <div className="stat-card__value">{issue.occurrence_count || 1}</div>
          </div>
          <div className="stat-card">
            <div className="stat-card__label">First Detected</div>
            <div className="stat-card__value" style={{ fontSize: '16px' }}>
              {formatDate(issue.first_detected_at)}
            </div>
          </div>
          <div className="stat-card">
            <div className="stat-card__label">Last Detected</div>
            <div className="stat-card__value" style={{ fontSize: '16px' }}>
              {formatDate(issue.last_detected_at)}
            </div>
          </div>
        </div>
      </s-section>

      <s-section>
        <div className="detail-card">
          <h3 className="detail-card__title">Description</h3>
          <p style={{ margin: 0, lineHeight: 1.6 }}>
            {issue.description || 'No description available.'}
          </p>
        </div>
      </s-section>

      {recommendation && (
        <s-section>
          <div className="detail-card">
            <h3 className="detail-card__title">Recommended Actions</h3>
            <p style={{ marginBottom: '12px', color: '#6d7175' }}>
              {recommendation.title}
            </p>
            <ol style={{ margin: 0, paddingLeft: '20px', lineHeight: 1.8 }}>
              {recommendation.steps.map((step, index) => (
                <li key={index}>{step}</li>
              ))}
            </ol>
          </div>
        </s-section>
      )}

      {issue.evidence && Object.keys(issue.evidence).length > 0 && (
        <s-section>
          <div className="detail-card">
            <h3 className="detail-card__title">Technical Details</h3>
            <div className="technical-details">
              {JSON.stringify(issue.evidence, null, 2)}
            </div>
          </div>
        </s-section>
      )}

      {issue.acknowledged_at && (
        <s-section>
          <div className="detail-card">
            <h3 className="detail-card__title">Acknowledgement</h3>
            <p style={{ margin: 0 }}>
              Acknowledged on {formatDate(issue.acknowledged_at)}
              {issue.acknowledged_by && ` by ${issue.acknowledged_by}`}
            </p>
          </div>
        </s-section>
      )}

      <s-section>
        <s-button-group>
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
