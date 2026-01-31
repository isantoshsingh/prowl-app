/**
 * Settings Page - App configuration and billing
 */

import { useState, useEffect } from 'react';
import { TitleBar } from '@shopify/app-bridge-react';
import { Loading, StatusBadge, BillingBanner } from '../components';
import { useToast } from '../hooks';
import api from '../services/api';

const SCAN_FREQUENCIES = [
  { value: 'daily', label: 'Daily' },
  { value: 'weekly', label: 'Weekly' }
];

export default function Settings() {
  const { showSuccess, showError } = useToast();
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [settings, setSettings] = useState(null);
  const [formData, setFormData] = useState({
    email_alerts_enabled: true,
    admin_alerts_enabled: true,
    alert_email: '',
    scan_frequency: 'daily'
  });

  useEffect(() => {
    loadSettings();
  }, []);

  const loadSettings = async () => {
    try {
      setLoading(true);
      const data = await api.getSettings();
      setSettings(data);
      setFormData({
        email_alerts_enabled: data.email_alerts_enabled ?? true,
        admin_alerts_enabled: data.admin_alerts_enabled ?? true,
        alert_email: data.alert_email || '',
        scan_frequency: data.scan_frequency || 'daily'
      });
    } catch (error) {
      showError('Failed to load settings');
      console.error('Load error:', error);
    } finally {
      setLoading(false);
    }
  };

  const handleChange = (field, value) => {
    setFormData(prev => ({ ...prev, [field]: value }));
  };

  const handleSubmit = async (e) => {
    e.preventDefault();
    try {
      setSaving(true);
      await api.updateSettings({ shop_setting: formData });
      showSuccess('Settings saved successfully');
      loadSettings();
    } catch (error) {
      showError('Failed to save settings');
      console.error('Save error:', error);
    } finally {
      setSaving(false);
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

  const billingStatus = settings?.billing_status || 'trial';
  const trialDaysRemaining = settings?.trial_days_remaining || 0;

  return (
    <>
      <TitleBar title="Settings" />

      <s-section>
        <BillingBanner
          billingStatus={billingStatus}
          trialDaysRemaining={trialDaysRemaining}
          onSubscribe={handleSubscribe}
        />
      </s-section>

      <s-section>
        <div className="detail-card">
          <h3 className="detail-card__title">Subscription Status</h3>
          <div className="card-grid" style={{ marginTop: '12px' }}>
            <div>
              <div style={{ fontSize: '13px', color: '#6d7175', marginBottom: '4px' }}>
                Status
              </div>
              <StatusBadge status={billingStatus} />
            </div>
            {billingStatus === 'trial' && (
              <div>
                <div style={{ fontSize: '13px', color: '#6d7175', marginBottom: '4px' }}>
                  Trial Days Remaining
                </div>
                <div style={{ fontSize: '20px', fontWeight: 600 }}>
                  {trialDaysRemaining}
                </div>
              </div>
            )}
            {settings?.trial_ends_at && billingStatus === 'trial' && (
              <div>
                <div style={{ fontSize: '13px', color: '#6d7175', marginBottom: '4px' }}>
                  Trial Ends
                </div>
                <div>
                  {new Date(settings.trial_ends_at).toLocaleDateString()}
                </div>
              </div>
            )}
          </div>
          {billingStatus !== 'active' && (
            <div style={{ marginTop: '16px' }}>
              <s-button variant="primary" onClick={handleSubscribe}>
                Subscribe Now - $10/month
              </s-button>
            </div>
          )}
        </div>
      </s-section>

      <s-section>
        <form onSubmit={handleSubmit}>
          <div className="detail-card">
            <h3 className="detail-card__title">Alert Preferences</h3>

            <div className="form-group" style={{ marginTop: '16px' }}>
              <label className="flex items-center gap-2" style={{ cursor: 'pointer' }}>
                <input
                  type="checkbox"
                  checked={formData.email_alerts_enabled}
                  onChange={(e) => handleChange('email_alerts_enabled', e.target.checked)}
                  style={{ width: '18px', height: '18px' }}
                />
                <span className="form-group__label" style={{ marginBottom: 0 }}>
                  Email Alerts
                </span>
              </label>
              <div className="form-group__help">
                Receive email notifications when high-severity issues are detected
              </div>
            </div>

            {formData.email_alerts_enabled && (
              <div className="form-group">
                <label className="form-group__label">Alert Email Address</label>
                <input
                  type="email"
                  value={formData.alert_email}
                  onChange={(e) => handleChange('alert_email', e.target.value)}
                  placeholder="alerts@yourstore.com"
                  style={{
                    width: '100%',
                    maxWidth: '400px',
                    padding: '10px 12px',
                    borderRadius: '4px',
                    border: '1px solid #c4cdd5',
                    fontSize: '14px'
                  }}
                />
                <div className="form-group__help">
                  Leave blank to use your store's default email
                </div>
              </div>
            )}

            <div className="form-group" style={{ marginTop: '16px' }}>
              <label className="flex items-center gap-2" style={{ cursor: 'pointer' }}>
                <input
                  type="checkbox"
                  checked={formData.admin_alerts_enabled}
                  onChange={(e) => handleChange('admin_alerts_enabled', e.target.checked)}
                  style={{ width: '18px', height: '18px' }}
                />
                <span className="form-group__label" style={{ marginBottom: 0 }}>
                  Admin Notifications
                </span>
              </label>
              <div className="form-group__help">
                Show notifications in the Shopify admin when issues are detected
              </div>
            </div>
          </div>

          <div className="detail-card" style={{ marginTop: '16px' }}>
            <h3 className="detail-card__title">Scan Frequency</h3>

            <div className="form-group" style={{ marginTop: '16px' }}>
              <label className="form-group__label">How often should we scan your product pages?</label>
              <select
                value={formData.scan_frequency}
                onChange={(e) => handleChange('scan_frequency', e.target.value)}
                style={{
                  padding: '10px 12px',
                  borderRadius: '4px',
                  border: '1px solid #c4cdd5',
                  fontSize: '14px',
                  minWidth: '200px'
                }}
              >
                {SCAN_FREQUENCIES.map(freq => (
                  <option key={freq.value} value={freq.value}>{freq.label}</option>
                ))}
              </select>
              <div className="form-group__help">
                Scans run automatically at the selected frequency. You can also trigger manual scans anytime.
              </div>
            </div>
          </div>

          <div className="detail-card" style={{ marginTop: '16px' }}>
            <h3 className="detail-card__title">Monitoring Limits</h3>
            <div style={{ marginTop: '12px' }}>
              <div style={{ fontSize: '13px', color: '#6d7175', marginBottom: '4px' }}>
                Maximum Monitored Pages
              </div>
              <div style={{ fontSize: '20px', fontWeight: 600 }}>
                {settings?.max_monitored_pages || 5}
              </div>
              <div className="form-group__help">
                Contact support to increase your monitoring limit
              </div>
            </div>
          </div>

          <div style={{ marginTop: '24px' }}>
            <s-button-group>
              <s-button variant="primary" type="submit" disabled={saving}>
                {saving ? 'Saving...' : 'Save Settings'}
              </s-button>
            </s-button-group>
          </div>
        </form>
      </s-section>
    </>
  );
}
