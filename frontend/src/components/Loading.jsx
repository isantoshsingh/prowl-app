/**
 * Loading component using Shopify Polaris spinner
 */

export default function Loading({ size = 'default' }) {
  return (
    <div className="loading">
      <s-spinner size={size} />
    </div>
  );
}
