"use client";

import { useMemo, useState } from "react";
import type { BatchQueueItem, BatchQueueItemStatus } from "@confluendo/ingestion-platform/core";
import {
  describeEffectiveQueueLifecycle,
  friendlyCategory,
  friendlyGeo,
  friendlyUnit,
  queueStatusLabels,
  type OperatorTone
} from "./ingestion-console-labels";

export type QueueGroupBy = "none" | "status" | "lifecycle" | "country" | "category" | "source";

interface IngestionQueueTableProps {
  items: BatchQueueItem[];
  sourceKey: string;
}

function needsAttention(item: BatchQueueItem): boolean {
  return describeEffectiveQueueLifecycle(item).tone === "danger" || item.blockReasons.length > 0;
}

function groupKey(item: BatchQueueItem, groupBy: QueueGroupBy): string {
  switch (groupBy) {
    case "status":
      return describeEffectiveQueueLifecycle(item).label;
    case "lifecycle":
      return describeEffectiveQueueLifecycle(item).lifecycle;
    case "country":
      return friendlyGeo(item.country);
    case "category":
      return friendlyCategory(item.category);
    case "source":
      return item.sourceKey;
    default:
      return "";
  }
}

export function IngestionQueueTable({ items, sourceKey }: IngestionQueueTableProps) {
  const [search, setSearch] = useState("");
  const [statusFilter, setStatusFilter] = useState("");
  const [countryFilter, setCountryFilter] = useState("");
  const [categoryFilter, setCategoryFilter] = useState("");
  const [sourceFilter, setSourceFilter] = useState("");
  const [attentionOnly, setAttentionOnly] = useState(false);
  const [groupBy, setGroupBy] = useState<QueueGroupBy>("lifecycle");
  const [expandedKeys, setExpandedKeys] = useState<Set<string>>(new Set());

  const countries = useMemo(
    () => [...new Set(items.map((item) => item.country))].sort(),
    [items]
  );
  const categories = useMemo(
    () => [...new Set(items.map((item) => item.category))].sort(),
    [items]
  );
  const sources = useMemo(
    () => [...new Set(items.map((item) => item.sourceKey))].sort(),
    [items]
  );
  const statuses = useMemo(
    () => [...new Set(items.map((item) => item.status))].sort(),
    [items]
  );

  const filtered = useMemo(() => {
    const needle = search.trim().toLowerCase();
    return items.filter((item) => {
      if (attentionOnly && !needsAttention(item)) {
        return false;
      }
      if (statusFilter && item.status !== statusFilter) {
        return false;
      }
      if (countryFilter && item.country !== countryFilter) {
        return false;
      }
      if (categoryFilter && item.category !== categoryFilter) {
        return false;
      }
      if (sourceFilter && item.sourceKey !== sourceFilter) {
        return false;
      }
      if (!needle) {
        return true;
      }
      const haystack = [
        item.unitKey,
        friendlyUnit(item.unitKey),
        item.country,
        item.geography,
        item.category,
        item.sourceKey,
        describeEffectiveQueueLifecycle(item).label,
        item.crossPlanPackageLifecycle?.planKey,
        ...item.blockReasons
      ]
        .join(" ")
        .toLowerCase();
      return haystack.includes(needle);
    });
  }, [
    items,
    search,
    statusFilter,
    countryFilter,
    categoryFilter,
    sourceFilter,
    attentionOnly
  ]);

  const grouped = useMemo(() => {
    if (groupBy === "none") {
      return [{ key: "", label: "", items: filtered }];
    }
    const map = new Map<string, BatchQueueItem[]>();
    for (const item of filtered) {
      const key = groupKey(item, groupBy);
      const bucket = map.get(key) ?? [];
      bucket.push(item);
      map.set(key, bucket);
    }
    return [...map.entries()]
      .sort(([a], [b]) => a.localeCompare(b))
      .map(([key, groupItems]) => ({
        key,
        label: key,
        items: groupItems.sort((a, b) => a.runOrder - b.runOrder)
      }));
  }, [filtered, groupBy]);

  function toggleExpanded(unitKey: string) {
    setExpandedKeys((prev) => {
      const next = new Set(prev);
      if (next.has(unitKey)) {
        next.delete(unitKey);
      } else {
        next.add(unitKey);
      }
      return next;
    });
  }

  return (
    <div className="admin-queue-console">
      <div className="admin-queue-toolbar" role="search" aria-label="Queue filters">
        <label className="admin-queue-filter">
          <span>Search</span>
          <input
            type="search"
            value={search}
            onChange={(event) => setSearch(event.target.value)}
            placeholder="Scope, geography, exception…"
          />
        </label>
        <label className="admin-queue-filter">
          <span>Plan-local stage</span>
          <select value={statusFilter} onChange={(event) => setStatusFilter(event.target.value)}>
            <option value="">All stages</option>
            {statuses.map((status) => (
              <option key={status} value={status}>
                {queueStatusLabels[status as BatchQueueItemStatus]}
              </option>
            ))}
          </select>
        </label>
        <label className="admin-queue-filter">
          <span>Country</span>
          <select value={countryFilter} onChange={(event) => setCountryFilter(event.target.value)}>
            <option value="">All countries</option>
            {countries.map((country) => (
              <option key={country} value={country}>
                {friendlyGeo(country)}
              </option>
            ))}
          </select>
        </label>
        <label className="admin-queue-filter">
          <span>Category</span>
          <select
            value={categoryFilter}
            onChange={(event) => setCategoryFilter(event.target.value)}
          >
            <option value="">All categories</option>
            {categories.map((category) => (
              <option key={category} value={category}>
                {friendlyCategory(category)}
              </option>
            ))}
          </select>
        </label>
        <label className="admin-queue-filter">
          <span>Source</span>
          <select value={sourceFilter} onChange={(event) => setSourceFilter(event.target.value)}>
            <option value="">All sources</option>
            {sources.map((source) => (
              <option key={source} value={source}>
                {source}
              </option>
            ))}
          </select>
        </label>
        <label className="admin-queue-filter admin-queue-filter-check">
          <input
            type="checkbox"
            checked={attentionOnly}
            onChange={(event) => setAttentionOnly(event.target.checked)}
          />
          <span>Exceptions only</span>
        </label>
        <label className="admin-queue-filter">
          <span>Group by</span>
          <select
            value={groupBy}
            onChange={(event) => setGroupBy(event.target.value as QueueGroupBy)}
          >
            <option value="lifecycle">Effective lifecycle</option>
            <option value="status">Effective status</option>
            <option value="country">Country</option>
            <option value="category">Category</option>
            <option value="source">Source</option>
            <option value="none">None</option>
          </select>
        </label>
      </div>

      <p className="admin-queue-summary">
        Showing <strong>{filtered.length}</strong> of {items.length} scopes · default source{" "}
        <code>{sourceKey}</code>
      </p>

      {grouped.map((group) => (
        <div className="admin-queue-group" key={group.key || "all"}>
          {group.label ? (
            <div className="admin-queue-group-heading">
              <h3>{group.label}</h3>
              <span>{group.items.length}</span>
            </div>
          ) : null}
          <div className="admin-table-wrap">
            <table className="admin-target-table admin-queue-table">
              <thead>
                <tr>
                  <th aria-label="Expand" />
                  <th>#</th>
                  <th>Scope</th>
                  <th>Country</th>
                  <th>Category</th>
                  <th>Effective lifecycle</th>
                  <th>Simulation</th>
                </tr>
              </thead>
              <tbody>
                {group.items.map((item) => (
                  <QueueRow
                    key={item.unitKey}
                    item={item}
                    expanded={expandedKeys.has(item.unitKey)}
                    onToggle={() => toggleExpanded(item.unitKey)}
                  />
                ))}
              </tbody>
            </table>
          </div>
        </div>
      ))}

      {filtered.length === 0 ? (
        <p className="admin-ux-empty">No scopes match the current filters.</p>
      ) : null}
    </div>
  );
}

function QueueRow({
  item,
  expanded,
  onToggle
}: {
  item: BatchQueueItem;
  expanded: boolean;
  onToggle: () => void;
}) {
  const lifecycle = describeEffectiveQueueLifecycle(item);
  const tone: OperatorTone = lifecycle.tone;
  const label = friendlyUnit(item.unitKey);
  const showRawKey = label !== item.unitKey;

  return (
    <>
      <tr className={needsAttention(item) ? "admin-queue-row-attention" : undefined}>
        <td>
          <button
            type="button"
            className="admin-queue-expand"
            onClick={onToggle}
            aria-expanded={expanded}
            aria-label={expanded ? "Hide scope details" : "Show scope details"}
          >
            {expanded ? "−" : "+"}
          </button>
        </td>
        <td>{item.runOrder}</td>
        <td>
          <strong>{showRawKey ? label : item.unitKey}</strong>
          {showRawKey ? <span className="admin-queue-subline">{item.geography}</span> : null}
        </td>
        <td>{friendlyGeo(item.country)}</td>
        <td>{friendlyCategory(item.category)}</td>
        <td>
          <span className={`admin-ux-status admin-ux-tone-${tone}`}>
            {lifecycle.label}
          </span>
          {lifecycle.detail ? <span className="admin-queue-subline">{lifecycle.detail}</span> : null}
        </td>
        <td>
          {item.dryRunReport
            ? `${item.dryRunReport.rowsProcessed} rows · no target write`
            : item.blockReasons.length > 0
              ? item.blockReasons.join(", ")
              : "—"}
        </td>
      </tr>
      {expanded ? (
        <tr className="admin-queue-details-row">
          <td colSpan={7}>
            <dl className="admin-queue-details">
              <div>
                <dt>Scope key</dt>
                <dd>
                  <code>{item.unitKey}</code>
                </dd>
              </div>
              <div>
                <dt>Source</dt>
                <dd>{item.sourceKey}</dd>
              </div>
              <div>
                <dt>Target</dt>
                <dd>
                  {item.targetKey} · {item.targetEnvironment}
                </dd>
              </div>
              <div>
                <dt>Priority</dt>
                <dd>{item.priority}</dd>
              </div>
              <div>
                <dt>Effective lifecycle</dt>
                <dd>{lifecycle.lifecycle}</dd>
              </div>
              <div>
                <dt>Plan-local status</dt>
                <dd>{queueStatusLabels[item.status]}</dd>
              </div>
              {item.crossPlanPackageLifecycle ? (
                <>
                  <div>
                    <dt>Previous plan</dt>
                    <dd>{item.crossPlanPackageLifecycle.planKey}</dd>
                  </div>
                  <div className="admin-queue-details-wide">
                    <dt>Previous delivery wave</dt>
                    <dd>
                      <code>{item.crossPlanPackageLifecycle.waveKey}</code>
                    </dd>
                  </div>
                </>
              ) : null}
              {item.blockReasons.length > 0 ? (
                <div className="admin-queue-details-wide">
                  <dt>Exceptions</dt>
                  <dd>{item.blockReasons.join("; ")}</dd>
                </div>
              ) : null}
            </dl>
          </td>
        </tr>
      ) : null}
    </>
  );
}
