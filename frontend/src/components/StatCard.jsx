/**
 * StatCard component for displaying statistics
 */

export default function StatCard({ label, value, variant }) {
  const valueClass = variant ? `stat-card__value--${variant}` : '';

  return (
    <div className="stat-card">
      <div className="stat-card__label">{label}</div>
      <div className={`stat-card__value ${valueClass}`}>{value}</div>
    </div>
  );
}
