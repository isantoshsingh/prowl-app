/**
 * API Service for PDP Diagnostics
 * Handles all communication with the Rails backend
 */

class ApiService {
  constructor() {
    this.baseUrl = '';
  }

  /**
   * Get session token from Shopify App Bridge
   */
  async getSessionToken() {
    if (window.shopify) {
      return await window.shopify.idToken();
    }
    return null;
  }

  /**
   * Make an authenticated API request
   */
  async request(endpoint, options = {}) {
    const token = await this.getSessionToken();

    const headers = {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      ...options.headers
    };

    if (token) {
      headers['Authorization'] = `Bearer ${token}`;
    }

    const response = await fetch(`${this.baseUrl}${endpoint}`, {
      ...options,
      headers,
      credentials: 'include'
    });

    if (!response.ok) {
      const error = new Error(`API Error: ${response.status}`);
      error.status = response.status;
      try {
        error.data = await response.json();
      } catch (e) {
        error.data = null;
      }
      throw error;
    }

    // Handle empty responses
    const text = await response.text();
    return text ? JSON.parse(text) : null;
  }

  // Dashboard
  async getDashboardStats() {
    return this.request('/dashboard/stats');
  }

  // Product Pages
  async getProductPages() {
    return this.request('/product_pages.json');
  }

  async getProductPage(id) {
    return this.request(`/product_pages/${id}.json`);
  }

  async createProductPage(data) {
    return this.request('/product_pages.json', {
      method: 'POST',
      body: JSON.stringify(data)
    });
  }

  async deleteProductPage(id) {
    return this.request(`/product_pages/${id}.json`, {
      method: 'DELETE'
    });
  }

  async rescanProductPage(id) {
    return this.request(`/product_pages/${id}/rescan.json`, {
      method: 'POST'
    });
  }

  // Issues
  async getIssues(params = {}) {
    const query = new URLSearchParams(params).toString();
    const endpoint = query ? `/issues.json?${query}` : '/issues.json';
    return this.request(endpoint);
  }

  async getIssue(id) {
    return this.request(`/issues/${id}.json`);
  }

  async acknowledgeIssue(id) {
    return this.request(`/issues/${id}/acknowledge.json`, {
      method: 'POST'
    });
  }

  // Scans
  async getScans(params = {}) {
    const query = new URLSearchParams(params).toString();
    const endpoint = query ? `/scans.json?${query}` : '/scans.json';
    return this.request(endpoint);
  }

  async getScan(id) {
    return this.request(`/scans/${id}.json`);
  }

  // Settings
  async getSettings() {
    return this.request('/settings.json');
  }

  async updateSettings(data) {
    return this.request('/settings.json', {
      method: 'PATCH',
      body: JSON.stringify(data)
    });
  }

  // Billing
  async createBillingCharge() {
    return this.request('/billing/create.json');
  }

  // Home data (for dashboard)
  async getHomeData() {
    return this.request('/home.json');
  }
}

export const api = new ApiService();
export default api;
