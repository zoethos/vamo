"use client";

import { useState } from "react";
import {
  controlEnvironmentLabel,
  type ControlEnvironment
} from "@/lib/control-environment";

export function ControlEnvironmentSwitcher({
  activeEnvironment,
  availableEnvironments,
  nextPath = "/admin/ingestion"
}: {
  activeEnvironment: ControlEnvironment;
  availableEnvironments: ControlEnvironment[];
  nextPath?: string;
}) {
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);

  return (
    <div className="admin-control-environment" aria-label="Control environment">
      <label htmlFor="control-environment-select">Workspace</label>
      <select
        aria-describedby={error ? "control-environment-error" : undefined}
        disabled={pending || availableEnvironments.length < 2}
        id="control-environment-select"
        onChange={async (event) => {
          const environment = event.target.value as ControlEnvironment;
          if (environment === activeEnvironment) return;
          setPending(true);
          setError(null);
          try {
            const response = await fetch("/api/admin/control-environment", {
              method: "POST",
              headers: { "content-type": "application/json" },
              body: JSON.stringify({ environment })
            });
            const body = (await response.json().catch(() => null)) as { error?: unknown } | null;
            if (!response.ok) {
              throw new Error(typeof body?.error === "string" ? body.error : "Workspace could not be changed.");
            }
            window.location.assign(nextPath);
          } catch (switchError) {
            setError(
              switchError instanceof Error ? switchError.message : "Workspace could not be changed."
            );
            setPending(false);
          }
        }}
        value={activeEnvironment}
      >
        {availableEnvironments.map((environment) => (
          <option key={environment} value={environment}>
            {controlEnvironmentLabel(environment)}
          </option>
        ))}
      </select>
      <span className={`admin-control-environment-status admin-control-environment-${activeEnvironment}`}>
        {pending ? "Switching workspace..." : controlEnvironmentLabel(activeEnvironment)}
      </span>
      {error ? (
        <span className="admin-control-environment-error" id="control-environment-error" role="alert">
          {error}
        </span>
      ) : null}
    </div>
  );
}
