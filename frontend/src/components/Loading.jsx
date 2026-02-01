/**
 * Loading component using Polaris Web Components
 */

export default function Loading({ size = 'large' }) {
  return (
    <s-box padding-block-start="800" padding-block-end="800">
      <s-inline-stack align="center" block-align="center">
        <s-spinner size={size}></s-spinner>
      </s-inline-stack>
    </s-box>
  );
}
