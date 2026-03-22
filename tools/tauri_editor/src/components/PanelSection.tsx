type PanelSectionProps = {
  label: string;
  title: string;
  children: React.ReactNode;
  compact?: boolean;
};

export function PanelSection({
  label,
  title,
  children,
  compact = false,
}: PanelSectionProps) {
  return (
    <section className={`panel ${compact ? "panel-compact" : ""}`}>
      <span className="section-label">{label}</span>
      <h3 className="panel-title">{title}</h3>
      <div className="panel-body">{children}</div>
    </section>
  );
}
