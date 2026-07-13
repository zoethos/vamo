"use client";

import { useMemo, useState } from "react";
import type { BatchQueueItem } from "@confluendo/ingestion-platform/core";
import {
  describeEffectiveQueueLifecycle,
  describeProductionPackageQueueNextAction,
  describeProductionPackageQueueStagingStatus,
  extractDryRunReportMetrics,
  friendlyUnit,
  isProductionPackageWaveSelectable,
  matchesProductionPackageApprovalQueueFilter,
  productionPackageApprovalQueueFilterLabels,
  type ProductionPackageApprovalQueueFilter
} from "./ingestion-console-labels";
import { OpenScopeButton } from "./open-scope-button";

interface DisplayColumn {
  key: string;
  label: string;
}

type StagingEvidenceHint = {
  status?: string;
};

export function ProductionPackageApprovalQueue({
  items,
  targetKey,
  eligibleCount,
  occupiedUnitKeys,
  stagingEvidenceByUnitKey,
  selectedUnitKeys,
  onSelectionChange,
  selectedUnitKey,
  onOpenScope
}: {
  items: BatchQueueItem[];
  targetKey: string;
  eligibleCount: number;
  occupiedUnitKeys: string[];
  stagingEvidenceByUnitKey: Record<string, StagingEvidenceHint>;
  selectedUnitKeys: string[];
  onSelectionChange: (unitKeys: string[]) => void;
  selectedUnitKey?: string | null;
  onOpenScope?: (unitKey: string) => void;
}) {
  const [filter, setFilter] = useState<ProductionPackageApprovalQueueFilter>("eligible_for_package");
  const occupied = useMemo(() => new Set(occupiedUnitKeys), [occupiedUnitKeys]);

  const displayColumns = useMemo<DisplayColumn[]>(() => {
    const columns = new Map<string, DisplayColumn>();
    for (const item of items) {
      for (const field of item.displayFields ?? []) {
        if (!columns.has(field.key)) {
          columns.set(field.key, { key: field.key, label: field.label });
        }
      }
    }
    return columns.size > 0 ? [...columns.values()] : [{ key: "category", label: "POI type" }];
  }, [items]);

  const rows = useMemo(() => {
    return items
      .filter((item) => item.targetKey === targetKey)
      .map((item) => {
        const staging = stagingEvidenceByUnitKey[item.unitKey];
        const stagingSucceeded = staging?.status === "succeeded";
        const eligibleForPackage = isProductionPackageWaveSelectable(item, {
          occupied: occupied.has(item.unitKey),
          stagingSucceeded
        });
        const metrics = extractDryRunReportMetrics(item.dryRunReport);
        const lifecycle = describeEffectiveQueueLifecycle(item);
        return {
          item,
          eligibleForPackage,
          expectedTargetWrites: metrics?.expectedTargetWrites ?? null,
          stagingStatus: describeProductionPackageQueueStagingStatus(
            staging ? stagingSucceeded : undefined
          ),
          packageStatus: lifecycle.label,
          packageStatusDetail: lifecycle.detail,
          nextAction: describeProductionPackageQueueNextAction(item, eligibleForPackage)
        };
      })
      .filter((row) =>
        matchesProductionPackageApprovalQueueFilter(row.item, filter, row.eligibleForPackage)
      )
      .sort((a, b) => a.item.runOrder - b.item.runOrder);
  }, [filter, items, occupied, stagingEvidenceByUnitKey, targetKey]);

  const selectedSet = useMemo(() => new Set(selectedUnitKeys), [selectedUnitKeys]);
  const selectableRows = rows.filter((row) => row.eligibleForPackage);
  const displayedRowLabel =
    filter === "eligible_for_package" && eligibleCount > rows.length
      ? `Showing first ${rows.length} of ${eligibleCount} eligible scope(s)`
      : rows.length === items.length
      ? `Showing ${rows.length} scope(s)`
      : `Showing ${rows.length} scope(s) for this filter`;

  function toggleUnit(unitKey: string) {
    if (selectedSet.has(unitKey)) {
      onSelectionChange(selectedUnitKeys.filter((key) => key !== unitKey));
      return;
    }
    onSelectionChange([...selectedUnitKeys, unitKey]);
  }

  function toggleAllVisible() {
    const visibleKeys = selectableRows.map((row) => row.item.unitKey);
    const allSelected = visibleKeys.every((key) => selectedSet.has(key));
    if (allSelected) {
      onSelectionChange(selectedUnitKeys.filter((key) => !visibleKeys.includes(key)));
      return;
    }
    onSelectionChange([...new Set([...selectedUnitKeys, ...visibleKeys])]);
  }

  return (
    <div className="admin-staging-approval-queue">
      <div className="admin-queue-toolbar" role="toolbar" aria-label="Production package queue filters">
        {(Object.keys(productionPackageApprovalQueueFilterLabels) as ProductionPackageApprovalQueueFilter[]).map(
          (key) => (
            <button
              key={key}
              type="button"
              className={`admin-queue-filter-chip${filter === key ? " is-active" : ""}`}
              onClick={() => setFilter(key)}
            >
              {productionPackageApprovalQueueFilterLabels[key]}
            </button>
          )
        )}
      </div>

      <p className="admin-queue-summary">
        {displayedRowLabel} · selected <strong>{selectedUnitKeys.length}</strong>
      </p>

      <div className="admin-table-wrap">
        <table className="admin-target-table admin-queue-table admin-staging-approval-table">
          <thead>
            <tr>
              <th>
                <input
                  type="checkbox"
                  aria-label="Select all eligible visible scopes"
                  checked={
                    selectableRows.length > 0 &&
                    selectableRows.every((row) => selectedSet.has(row.item.unitKey))
                  }
                  disabled={selectableRows.length === 0}
                  onChange={toggleAllVisible}
                />
              </th>
              <th>#</th>
              <th>Scope</th>
              {displayColumns.map((column) => (
                <th key={column.key}>{column.label}</th>
              ))}
              <th>Expected target writes</th>
              <th>Staging evidence</th>
              <th>Effective delivery status</th>
              <th>Next action</th>
              {onOpenScope ? <th>Context</th> : null}
            </tr>
          </thead>
          <tbody>
            {rows.map((row) => (
              <tr key={row.item.unitKey}>
                <td>
                  <input
                    type="checkbox"
                    aria-label={`Select ${row.item.unitKey}`}
                    checked={selectedSet.has(row.item.unitKey)}
                    disabled={!row.eligibleForPackage}
                    onChange={() => toggleUnit(row.item.unitKey)}
                  />
                </td>
                <td>{row.item.runOrder}</td>
                <td>
                  <strong>{friendlyUnit(row.item.unitKey)}</strong>
                  <code className="admin-evidence-code">{row.item.unitKey}</code>
                </td>
                {displayColumns.map((column) => {
                  const field = row.item.displayFields?.find((entry) => entry.key === column.key);
                  return (
                    <td key={column.key}>
                      <strong>{field?.value ?? row.item.category}</strong>
                      {field?.detail ? (
                        <code className="admin-evidence-code">{field.detail}</code>
                      ) : null}
                    </td>
                  );
                })}
                <td>{row.expectedTargetWrites ?? "—"}</td>
                <td>{row.stagingStatus}</td>
                <td>
                  <strong>{row.packageStatus}</strong>
                  {row.packageStatusDetail ? (
                    <code className="admin-evidence-code">{row.packageStatusDetail}</code>
                  ) : null}
                </td>
                <td>{row.nextAction}</td>
                {onOpenScope ? (
                  <td>
                    <OpenScopeButton
                      onOpen={onOpenScope}
                      selected={selectedUnitKey === row.item.unitKey}
                      unitKey={row.item.unitKey}
                    />
                  </td>
                ) : null}
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {rows.length === 0 ? (
        <p className="admin-ux-empty">No scopes match the current production package filter.</p>
      ) : null}
    </div>
  );
}
