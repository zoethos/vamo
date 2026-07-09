"use client";

import { useState } from "react";

export function CopyableMonospace({
  value,
  displayValue,
  label,
  className = "admin-evidence-code"
}: {
  value: string;
  displayValue?: string;
  label?: string;
  className?: string;
}) {
  const [copied, setCopied] = useState(false);
  const shown = displayValue ?? value;

  async function copy() {
    try {
      await navigator.clipboard.writeText(value);
      setCopied(true);
      window.setTimeout(() => setCopied(false), 1600);
    } catch {
      setCopied(false);
    }
  }

  return (
    <span className="admin-copyable-mono">
      <code className={className} title={value}>
        {shown}
      </code>
      <button
        type="button"
        className="admin-copyable-mono-button"
        onClick={() => void copy()}
        aria-label={label ?? `Copy ${value}`}
      >
        {copied ? "Copied" : "Copy"}
      </button>
    </span>
  );
}

export function CopyableCommandBlock({ command }: { command: string }) {
  const [copied, setCopied] = useState(false);

  async function copy() {
    try {
      await navigator.clipboard.writeText(command);
      setCopied(true);
      window.setTimeout(() => setCopied(false), 1600);
    } catch {
      setCopied(false);
    }
  }

  return (
    <div className="admin-agent-cli-block">
      <pre>
        <code>{command}</code>
      </pre>
      <button type="button" className="admin-command admin-command-neutral" onClick={() => void copy()}>
        {copied ? "Copied" : "Copy command"}
      </button>
    </div>
  );
}
