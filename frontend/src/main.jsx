import React from 'react';
import ReactDOM from 'react-dom/client';
import { BrowserRouter } from 'react-router-dom';
import App from './App';

// Only import styles if not in Rails layout (which already has them)
if (!document.querySelector('link[href*="polaris.css"]')) {
  import('./styles.css');
}

// Wait for DOM to be ready
function init() {
  const rootElement = document.getElementById('root');

  if (rootElement) {
    // Clear any loading content
    rootElement.innerHTML = '';

    ReactDOM.createRoot(rootElement).render(
      <React.StrictMode>
        <BrowserRouter>
          <App />
        </BrowserRouter>
      </React.StrictMode>
    );
  } else {
    console.error('Root element not found');
  }
}

// Initialize when DOM is ready
if (document.readyState === 'loading') {
  document.addEventListener('DOMContentLoaded', init);
} else {
  init();
}
