"use client";

import { useEffect, useState } from "react";

type DashboardTheme = "light" | "dark";

type DashboardThemeToggleProps = {
  defaultTheme: DashboardTheme;
  label: string;
  rootId: string;
  storageKey: string;
};

function isDashboardTheme(value: string | null): value is DashboardTheme {
  return value === "light" || value === "dark";
}

function applyTheme(rootId: string, theme: DashboardTheme) {
  const root = document.getElementById(rootId);
  if (!root) return;
  root.dataset.theme = theme;
  root.style.colorScheme = theme;
}

function SunIcon() {
  return (
    <svg aria-hidden="true" viewBox="0 0 24 24">
      <circle cx="12" cy="12" r="4.25" />
      <path d="M12 2.5v3M12 18.5v3M4.32 4.32l2.12 2.12M17.56 17.56l2.12 2.12M2.5 12h3M18.5 12h3M4.32 19.68l2.12-2.12M17.56 6.44l2.12-2.12" />
    </svg>
  );
}

function MoonIcon() {
  return (
    <svg aria-hidden="true" viewBox="0 0 24 24">
      <path d="M20.25 14.4A7.85 7.85 0 0 1 9.6 3.75a8.35 8.35 0 1 0 10.65 10.65Z" />
    </svg>
  );
}

export function DashboardThemeToggle({
  defaultTheme,
  label,
  rootId,
  storageKey,
}: DashboardThemeToggleProps) {
  const [theme, setTheme] = useState<DashboardTheme>(defaultTheme);

  useEffect(() => {
    let nextTheme = defaultTheme;
    try {
      const storedTheme = window.localStorage.getItem(storageKey);
      if (isDashboardTheme(storedTheme)) {
        nextTheme = storedTheme;
      }
    } catch {
      nextTheme = defaultTheme;
    }
    setTheme(nextTheme);
    applyTheme(rootId, nextTheme);
  }, [defaultTheme, rootId, storageKey]);

  const nextTheme: DashboardTheme = theme === "dark" ? "light" : "dark";

  function onToggle() {
    setTheme(nextTheme);
    applyTheme(rootId, nextTheme);
    try {
      window.localStorage.setItem(storageKey, nextTheme);
    } catch {
      // The visual state still changes when storage is unavailable.
    }
  }

  return (
    <button
      aria-label={`${label}: switch to ${nextTheme} mode`}
      aria-pressed={theme === "dark"}
      className="dashboard-theme-toggle"
      data-theme-toggle-state={theme}
      onClick={onToggle}
      title={`Switch to ${nextTheme} mode`}
      type="button"
    >
      <span className="dashboard-theme-toggle-icon">
        {theme === "dark" ? <MoonIcon /> : <SunIcon />}
      </span>
      <span className="dashboard-theme-toggle-track" aria-hidden="true">
        <span className="dashboard-theme-toggle-thumb" />
      </span>
      <span className="dashboard-theme-toggle-label">
        {theme === "dark" ? "Dark" : "Light"}
      </span>
    </button>
  );
}
