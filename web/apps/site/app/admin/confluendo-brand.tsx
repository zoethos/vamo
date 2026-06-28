import type { CSSProperties } from "react";

type ConfluendoMarkVariant = "accent" | "spectrum";

const STREAM_COLORS: Record<ConfluendoMarkVariant, readonly [string, string, string, string]> = {
  // Dependable brand mark: two soft + two accent blue streams converging.
  accent: ["#6FA8C7", "#6FA8C7", "#3B6EA5", "#3B6EA5"],
  // Confluence Spectrum: four bright sources meeting one calm channel.
  spectrum: ["#FF6B5C", "#FFB03A", "#1FB6A6", "#5B6BF0"]
};

/**
 * Confluendo brand mark — four streams converging into one current.
 *
 * The converging line and node use `currentColor` so the mark reads correctly on
 * both light and dark surfaces (it inherits the brand link's text color). The
 * stream colors stay constant for brand recognition.
 */
export function ConfluendoMark({
  size = 32,
  variant = "accent",
  className,
  title
}: {
  size?: number;
  variant?: ConfluendoMarkVariant;
  className?: string;
  title?: string;
}) {
  const streams = STREAM_COLORS[variant];
  const style: CSSProperties = { width: size, height: size };
  return (
    <svg
      className={className}
      style={style}
      viewBox="0 0 64 64"
      fill="none"
      role={title ? "img" : undefined}
      aria-hidden={title ? undefined : true}
      aria-label={title}
    >
      <path d="M6 14 C 22 14, 28 32, 40 32" stroke={streams[0]} strokeWidth="3.4" strokeLinecap="round" />
      <path d="M6 25 C 24 25, 30 32, 40 32" stroke={streams[1]} strokeWidth="3.4" strokeLinecap="round" />
      <path d="M6 39 C 24 39, 30 32, 40 32" stroke={streams[2]} strokeWidth="3.4" strokeLinecap="round" />
      <path d="M6 50 C 22 50, 28 32, 40 32" stroke={streams[3]} strokeWidth="3.4" strokeLinecap="round" />
      <line x1="40" y1="32" x2="58" y2="32" stroke="currentColor" strokeWidth="4.6" strokeLinecap="round" />
      <circle cx="40" cy="32" r="5" fill="currentColor" />
    </svg>
  );
}
