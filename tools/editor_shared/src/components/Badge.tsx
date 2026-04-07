type BadgeProps = {
  tone?: "accent" | "muted" | "warning" | "danger" | "success";
  children: React.ReactNode;
  title?: string;
};

export function Badge({ tone = "muted", children, title }: BadgeProps) {
  return (
    <span className={`badge badge-${tone}`} title={title}>
      {children}
    </span>
  );
}
