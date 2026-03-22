type BadgeProps = {
  tone?: "accent" | "muted" | "warning" | "danger" | "success";
  children: React.ReactNode;
};

export function Badge({ tone = "muted", children }: BadgeProps) {
  return <span className={`badge badge-${tone}`}>{children}</span>;
}
