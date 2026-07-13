"use client";

export function OpenScopeButton({
  unitKey,
  selected,
  onOpen
}: {
  unitKey: string;
  selected: boolean;
  onOpen: (unitKey: string) => void;
}) {
  return (
    <button
      aria-label={
        selected
          ? `${unitKey} is open in scope context`
          : `Open scope context for ${unitKey}`
      }
      aria-pressed={selected}
      className={`admin-open-scope-button${selected ? " is-selected" : ""}`}
      onClick={() => onOpen(unitKey)}
      title="Open scope context"
      type="button"
    >
      <span aria-hidden="true" className="admin-open-scope-button-icon">
        ◎
      </span>
      <span className="admin-open-scope-button-label">Open scope</span>
    </button>
  );
}
