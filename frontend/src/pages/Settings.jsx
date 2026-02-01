/**
 * Settings Page - App configuration and billing
 */

import { useState, useEffect } from 'react';
import { TitleBar } from '@shopify/app-bridge-react';
import { Loading, StatusBadge, BillingBanner, StatCard } from '../components';
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
        <s-block-stack gap="300">
          <s-text variant="headingMd">Subscription Status</s-text>
          <s-card>
            <s-box padding="400">
              <s-block-stack gap="400">
                <div className="card-grid">
                  <s-block-stack gap="100">
                    <s-text variant="bodySm" tone="subdued">Status</s-text>
                    <StatusBadge status={billingStatus} />
                  </s-block-stack>
                  {billingStatus === 'trial' && (
                    <s-block-stack gap="100">
                      <s-text variant="bodySm" tone="subdued">Trial Days Remaining</s-text>
                      <s-text variant="headingLg">{trialDaysRemaining}</s-text>
                    </s-block-stack>
                  )}
                  {settings?.trial_ends_at && billingStatus === 'trial' && (
                    <s-block-stack gap="100">
                      <s-text variant="bodySm" tone="subdued">Trial Ends</s-text>
                      <s-text variant="bodyMd">
                        {new Date(settings.trial_ends_at).toLocaleDateString()}
                      </s-text>
                    </s-block-stack>
                  )}
                </div>
                {billingStatus !== 'active' && (
                  <s-button variant="primary" onClick={handleSubscribe}>
                    Subscribe Now - $10/month
                  </s-button>
                )}
              </s-block-stack>
            </s-box>
          </s-card>
        </s-block-stack>
      </s-section>

      <s-section>
        <form onSubmit={handleSubmit}>
          <s-block-stack gap="400">
            <s-block-stack gap="300">
              <s-text variant="headingMd">Alert Preferences</s-text>
              <s-card>
                <s-box padding="400">
                  <s-block-stack gap="400">
                    <s-block-stack gap="100">
                      <s-checkbox
                        checked={formData.email_alerts_enabled}
                        onChange={(e) => handleChange('email_alerts_enabled', e.target.checked)}
                      >
                        Email Alerts
                      </s-checkbox>
                      <s-text variant="bodySm" tone="subdued">
                        Receive email notifications when high-severity issues are detected
                      </s-text>
                    </s-block-stack>

                    {formData.email_alerts_enabled && (
                      <s-text-field
                        label="Alert Email Address"
                        type="email"
                        value={formData.alert_email}
                        onChange={(e) => handleChange('alert_email', e.target.value)}
                        placeholder="alerts@yourstore.com"
                        help-text="Leave blank to use your store's default email"
                      />
                    )}

                    <s-block-stack gap="100">
                      <s-checkbox
                        checked={formData.admin_alerts_enabled}
                        onChange={(e) => handleChange('admin_alerts_enabled', e.target.checked)}
                      >
                        Admin Notifications
                      </s-checkbox>
                      <s-text variant="bodySm" tone="subdued">
                        Show notifications in the Shopify admin when issues are detected
                      </s-text>
                    </s-block-stack>
                  </s-block-stack>
                </s-box>
              </s-card>
            </s-block-stack>

            <s-block-stack gap="300">
              <s-text variant="headingMd">Scan Frequency</s-text>
              <s-card>
                <s-box padding="400">
                  <s-block-stack gap="200">
                    <s-select
                      label="How often should we scan your product pages?"
                      value={formData.scan_frequency}
                      onChange={(e) => handleChange('scan_frequency', e.target.value)}
                      options={JSON.stringify(SCAN_FREQUENCIES)}
                    />
                    <s-text variant="bodySm" tone="subdued">
                      Scans run automatically at the selected frequency. You can also trigger manual scans anytime.
                    </s-text>
                  </s-block-stack>
                </s-box>
              </s-card>
            </s-block-stack>

            <s-block-stack gap="300">
              <s-text variant="headingMd">Monitoring Limits</s-text>
              <s-card>
                <s-box padding="400">
                  <s-block-stack gap="100">
                    <s-text variant="bodySm" tone="subdued">Maximum Monitored Pages</s-text>
                    <s-text variant="headingLg">{settings?.max_monitored_pages || 5}</s-text>
                    <s-text variant="bodySm" tone="subdued">
                      Contact support to increase your monitoring limit
                    </s-text>
                  </s-block-stack>
                </s-box>
              </s-card>
            </s-block-stack>

            <s-button-group>
              <s-button variant="primary" type="submit" disabled={saving}>
                {saving ? 'Saving...' : 'Save Settings'}
              </s-button>
            </s-button-group>
          </s-block-stack>
        </form>
      </s-section>
    </>
  );
}
