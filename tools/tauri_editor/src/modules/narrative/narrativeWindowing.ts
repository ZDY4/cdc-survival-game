export const NARRATIVE_LAB_WINDOW_LABEL = "narrative-lab";

export function buildNarrativeLabWindowUrl(): string {
  const params = new URLSearchParams({
    surface: "narrative-lab",
  });
  return `/?${params.toString()}`;
}
