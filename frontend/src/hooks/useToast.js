/**
 * Custom hook for showing toast notifications via Shopify App Bridge
 */

export function useToast() {
  const showToast = (message, options = {}) => {
    if (window.shopify?.toast) {
      window.shopify.toast.show(message, {
        duration: options.duration || 5000,
        isError: options.isError || false
      });
    } else {
      // Fallback for development without App Bridge
      console.log(`Toast: ${message}`, options);
    }
  };

  const showSuccess = (message) => {
    showToast(message, { isError: false });
  };

  const showError = (message) => {
    showToast(message, { isError: true });
  };

  return { showToast, showSuccess, showError };
}

export default useToast;
