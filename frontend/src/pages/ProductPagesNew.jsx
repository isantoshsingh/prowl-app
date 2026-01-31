/**
 * Add Products Page - Select products to monitor using Shopify Resource Picker
 */

import { useState, useEffect } from 'react';
import { useNavigate } from 'react-router-dom';
import { TitleBar } from '@shopify/app-bridge-react';
import { Loading, EmptyState } from '../components';
import { useToast } from '../hooks';
import api from '../services/api';

export default function ProductPagesNew() {
  const navigate = useNavigate();
  const { showSuccess, showError } = useToast();
  const [loading, setLoading] = useState(false);
  const [selectedProducts, setSelectedProducts] = useState([]);
  const [existingHandles, setExistingHandles] = useState([]);
  const [maxPages, setMaxPages] = useState(5);
  const [currentCount, setCurrentCount] = useState(0);

  useEffect(() => {
    loadExistingProducts();
  }, []);

  const loadExistingProducts = async () => {
    try {
      const [pages, settings] = await Promise.all([
        api.getProductPages(),
        api.getSettings()
      ]);
      const productPages = pages?.product_pages || pages || [];
      setExistingHandles(productPages.map(p => p.handle));
      setCurrentCount(productPages.length);
      setMaxPages(settings?.max_monitored_pages || 5);
    } catch (error) {
      console.error('Failed to load existing products:', error);
    }
  };

  const openResourcePicker = async () => {
    if (!window.shopify?.resourcePicker) {
      showError('Resource picker not available');
      return;
    }

    try {
      const remainingSlots = maxPages - currentCount;
      if (remainingSlots <= 0) {
        showError(`You can only monitor up to ${maxPages} products`);
        return;
      }

      const selected = await window.shopify.resourcePicker({
        type: 'product',
        multiple: true,
        selectionIds: [],
        filter: {
          hidden: false,
          variants: false
        }
      });

      if (selected && selected.length > 0) {
        // Filter out already monitored products
        const newProducts = selected.filter(
          product => !existingHandles.includes(product.handle)
        );

        if (newProducts.length === 0) {
          showError('All selected products are already being monitored');
          return;
        }

        // Limit to remaining slots
        const productsToAdd = newProducts.slice(0, remainingSlots);
        if (newProducts.length > remainingSlots) {
          showError(`Only ${remainingSlots} product slots available. Some products were not added.`);
        }

        setSelectedProducts(productsToAdd);
      }
    } catch (error) {
      if (error.message !== 'Picker was cancelled') {
        showError('Failed to open product picker');
        console.error('Resource picker error:', error);
      }
    }
  };

  const handleSubmit = async () => {
    if (selectedProducts.length === 0) {
      showError('Please select at least one product');
      return;
    }

    try {
      setLoading(true);

      // Create product pages one by one
      const results = await Promise.allSettled(
        selectedProducts.map(product =>
          api.createProductPage({
            product_page: {
              shopify_product_id: product.id.replace('gid://shopify/Product/', ''),
              handle: product.handle,
              title: product.title
            }
          })
        )
      );

      const succeeded = results.filter(r => r.status === 'fulfilled').length;
      const failed = results.filter(r => r.status === 'rejected').length;

      if (succeeded > 0) {
        showSuccess(`${succeeded} product(s) added for monitoring`);
      }
      if (failed > 0) {
        showError(`${failed} product(s) failed to add`);
      }

      navigate('/product_pages');
    } catch (error) {
      showError('Failed to add products');
      console.error('Submit error:', error);
    } finally {
      setLoading(false);
    }
  };

  const removeProduct = (handle) => {
    setSelectedProducts(selectedProducts.filter(p => p.handle !== handle));
  };

  const remainingSlots = maxPages - currentCount;

  return (
    <>
      <TitleBar title="Add Products">
        <button
          variant="primary"
          onClick={handleSubmit}
          disabled={loading || selectedProducts.length === 0}
        >
          {loading ? 'Adding...' : `Add ${selectedProducts.length} Product(s)`}
        </button>
      </TitleBar>

      <s-section>
        <s-banner tone="info">
          <s-text>
            You can monitor up to {maxPages} product pages. Currently using {currentCount} of {maxPages} slots
            ({remainingSlots} remaining).
          </s-text>
        </s-banner>
      </s-section>

      <s-section>
        <div className="section">
          <div className="section__header">
            <h2 className="section__title">Select Products</h2>
          </div>
          <div className="detail-card">
            <p style={{ marginBottom: '16px', color: '#6d7175' }}>
              Choose products from your store to monitor. We'll scan these product pages daily
              and alert you if any issues are detected.
            </p>
            <s-button
              variant="primary"
              onClick={openResourcePicker}
              disabled={remainingSlots <= 0}
            >
              Browse Products
            </s-button>
          </div>
        </div>
      </s-section>

      {selectedProducts.length > 0 && (
        <s-section>
          <div className="section">
            <div className="section__header">
              <h2 className="section__title">Selected Products ({selectedProducts.length})</h2>
            </div>
            <table className="data-table">
              <thead>
                <tr>
                  <th>Product</th>
                  <th>Handle</th>
                  <th>Action</th>
                </tr>
              </thead>
              <tbody>
                {selectedProducts.map((product) => (
                  <tr key={product.id}>
                    <td>
                      <div className="flex items-center gap-2">
                        {product.images?.[0]?.originalSrc && (
                          <img
                            src={product.images[0].originalSrc}
                            alt={product.title}
                            style={{ width: 40, height: 40, objectFit: 'cover', borderRadius: 4 }}
                          />
                        )}
                        <span>{product.title}</span>
                      </div>
                    </td>
                    <td>{product.handle}</td>
                    <td>
                      <s-button
                        size="slim"
                        tone="critical"
                        variant="plain"
                        onClick={() => removeProduct(product.handle)}
                      >
                        Remove
                      </s-button>
                    </td>
                  </tr>
                ))}
              </tbody>
            </table>
          </div>
        </s-section>
      )}

      {selectedProducts.length === 0 && (
        <s-section>
          <EmptyState
            icon="📦"
            title="No products selected"
            description="Click 'Browse Products' to select products from your store."
          />
        </s-section>
      )}
    </>
  );
}
