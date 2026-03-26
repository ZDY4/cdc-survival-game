type BaseFieldProps = {
  label: string;
  hint?: string;
};

type TextFieldProps = BaseFieldProps & {
  value: string;
  onChange: (value: string) => void;
  placeholder?: string;
};

type NumberFieldProps = BaseFieldProps & {
  value: number;
  onChange: (value: number) => void;
  step?: number;
  min?: number;
};

type CheckboxFieldProps = BaseFieldProps & {
  value: boolean;
  onChange: (value: boolean) => void;
};

export type SelectOption = {
  value: string;
  label: string;
};

type SelectFieldProps = BaseFieldProps & {
  value: string;
  onChange: (value: string) => void;
  options: Array<string | SelectOption>;
  allowBlank?: boolean;
};

type TokenListFieldProps = BaseFieldProps & {
  values: string[];
  onChange: (values: string[]) => void;
  placeholder?: string;
};

type NumberMapFieldProps = BaseFieldProps & {
  value: Record<string, number>;
  onChange: (value: Record<string, number>) => void;
};

type JsonFieldProps = BaseFieldProps & {
  value: string;
  onChange: (value: string) => void;
};

function FieldFrame({
  label,
  hint,
  children,
}: BaseFieldProps & { children: React.ReactNode }) {
  return (
    <label className="field">
      <span className="field-label">{label}</span>
      {children}
      {hint ? <span className="field-hint">{hint}</span> : null}
    </label>
  );
}

export function TextField({
  label,
  hint,
  value,
  onChange,
  placeholder,
}: TextFieldProps) {
  return (
    <FieldFrame label={label} hint={hint}>
      <input
        className="field-input"
        type="text"
        value={value}
        placeholder={placeholder}
        onChange={(event) => onChange(event.target.value)}
      />
    </FieldFrame>
  );
}

export function TextareaField({
  label,
  hint,
  value,
  onChange,
  placeholder,
}: TextFieldProps) {
  return (
    <FieldFrame label={label} hint={hint}>
      <textarea
        className="field-input field-textarea"
        value={value}
        placeholder={placeholder}
        onChange={(event) => onChange(event.target.value)}
      />
    </FieldFrame>
  );
}

export function NumberField({
  label,
  hint,
  value,
  onChange,
  step = 1,
  min,
}: NumberFieldProps) {
  return (
    <FieldFrame label={label} hint={hint}>
      <input
        className="field-input"
        type="number"
        value={Number.isFinite(value) ? value : 0}
        step={step}
        min={min}
        onChange={(event) => onChange(Number(event.target.value))}
      />
    </FieldFrame>
  );
}

export function CheckboxField({
  label,
  hint,
  value,
  onChange,
}: CheckboxFieldProps) {
  return (
    <label className="toggle-field">
      <div>
        <span className="field-label">{label}</span>
        {hint ? <span className="field-hint">{hint}</span> : null}
      </div>
      <input
        className="toggle-input"
        type="checkbox"
        checked={value}
        onChange={(event) => onChange(event.target.checked)}
      />
    </label>
  );
}

export function SelectField({
  label,
  hint,
  value,
  onChange,
  options,
  allowBlank = true,
}: SelectFieldProps) {
  const normalizedOptions = options.map((option) =>
    typeof option === "string" ? { value: option, label: option } : option,
  );

  return (
    <FieldFrame label={label} hint={hint}>
      <select
        className="field-input"
        value={value}
        onChange={(event) => onChange(event.target.value)}
      >
        {allowBlank ? <option value="">None</option> : null}
        {normalizedOptions.map((option) => (
          <option key={option.value} value={option.value}>
            {option.label}
          </option>
        ))}
      </select>
    </FieldFrame>
  );
}

export function TokenListField({
  label,
  hint,
  values,
  onChange,
  placeholder,
}: TokenListFieldProps) {
  return (
    <FieldFrame label={label} hint={hint}>
      <textarea
        className="field-input field-textarea"
        value={values.join("\n")}
        placeholder={placeholder ?? "One entry per line"}
        onChange={(event) =>
          onChange(
            event.target.value
              .split("\n")
              .map((value) => value.trim())
              .filter(Boolean),
          )
        }
      />
    </FieldFrame>
  );
}

export function NumberMapField({
  label,
  hint,
  value,
  onChange,
}: NumberMapFieldProps) {
  const rows = Object.entries(value)
    .map(([key, amount]) => `${key}=${amount}`)
    .join("\n");

  return (
    <FieldFrame label={label} hint={hint}>
      <textarea
        className="field-input field-textarea"
        value={rows}
        placeholder={"strength=2\nagility=1"}
        onChange={(event) => {
          const next: Record<string, number> = {};
          for (const rawLine of event.target.value.split("\n")) {
            const line = rawLine.trim();
            if (!line) {
              continue;
            }
            const [key, amount] = line.split("=");
            if (!key || amount === undefined) {
              continue;
            }
            next[key.trim()] = Number(amount.trim());
          }
          onChange(next);
        }}
      />
    </FieldFrame>
  );
}

export function JsonField({ label, hint, value, onChange }: JsonFieldProps) {
  return (
    <FieldFrame label={label} hint={hint}>
      <textarea
        className="field-input field-textarea field-code"
        value={value}
        onChange={(event) => onChange(event.target.value)}
      />
    </FieldFrame>
  );
}
