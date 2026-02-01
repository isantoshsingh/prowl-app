/**
 * Add Products Page - Select products using Shopify Resource Picker and Polaris Web Components
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
        const newProducts = selected.filter(
          product => !existingHandles.includes(product.handle)
        );

        if (newProducts.length === 0) {
          showError('All selected products are already being monitored');
          return;
        }

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
        <s-banner tone="info" title={`${remainingSlots} slots remaining`}>
          <s-text>
            You can monitor up to {maxPages} product pages. Currently using {currentCount} of {maxPages} slots.
          </s-text>
        </s-banner>
      </s-section>

      <s-section>
        <s-card>
          <s-box padding="400">
            <s-block-stack gap="400">
              <s-text variant="headingMd">Select Products</s-text>
              <s-text tone="subdued">
                Choose products from your store to monitor. We'll scan these product pages daily
                and alert you if any issues are detected.
              </s-text>
              <s-button
                onClick={openResourcePicker}
                disabled={remainingSlots <= 0}
              >
                Browse Products
              </s-button>
            </s-block-stack>
          </s-box>
        </s-card>
      </s-section>

      {selectedProducts.length > 0 && (
        <s-section>
          <s-text variant="headingMd">Selected Products ({selectedProducts.length})</s-text>
          <s-box padding-block-start="400">
            <s-card>
              <s-data-table>
                <s-data-table-header>
                  <s-data-table-row>
                    <s-data-table-cell>Product</s-data-table-cell>
                    <s-data-table-cell>Handle</s-data-table-cell>
                    <s-data-table-cell>Action</s-data-table-cell>
                  </s-data-table-row>
                </s-data-table-header>
                <s-data-table-body>
                  {selectedProducts.map((product) => (
                    <s-data-table-row key={product.id}>
                      <s-data-table-cell>
                        <s-inline-stack gap="300" block-align="center">
                          {product.images?.[0]?.originalSrc && (
                            <s-thumbnail
                              source={product.images[0].originalSrc}
                              alt={product.title}
                              size="small"
                            />
                          )}
                          <s-text>{product.title}</s-text>
                        </s-inline-stack>
                      </s-data-table-cell>
                      <s-data-table-cell>
                        <s-text tone="subdued">{product.handle}</s-text>
                      </s-data-table-cell>
                      <s-data-table-cell>
                        <s-button
                          size="slim"
                          tone="critical"
                          variant="plain"
                          onClick={() => removeProduct(product.handle)}
                        >
                          Remove
                        </s-button>
                      </s-data-table-cell>
                    </s-data-table-row>
                  ))}
                </s-data-table-body>
              </s-data-table>
            </s-card>
          </s-box>
        </s-section>
      )}

      {selectedProducts.length === 0 && (
        <s-section>
          <EmptyState
            title="No products selected"
            description="Click 'Browse Products' to select products from your store."
          />
        </s-section>
      )}
    </>
  );
}
