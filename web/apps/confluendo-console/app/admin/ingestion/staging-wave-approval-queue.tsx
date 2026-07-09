"use client";

import { useMemo, useState } from "react";
import type { BatchQueueItem, BatchQueueLatestWave } from "@confluendo/ingestion-platform/core";
import { presentVamoPoiType } from "@confluendo/ingestion-platform/core/vamo-place-intelligence-presentation";
import {
  describeStagingQueueEvidenceStatus,
  describeStagingQueueNextAction,
  extractDryRunReportMetrics,
  friendlyUnit,
  isStagingWaveSelectable,
  matchesStagingApprovalQueueFilter,
  queueStatusLabels,
  stagingApprovalQueueFilterLabels,
  type StagingApprovalQueueFilter
} from "./ingestion-console-labels";

export function StagingWaveApprovalQueue({
  items,
  latestWave,
  selectedUnitKeys,
  onSelectionChange
}: {
  items: BatchQueueItem[];
  latestWave?: BatchQueueLatestWave | null;
  selectedUnitKeys: string[];
  onSelectionChange: (unitKeys: string[]) => void;
}) {
  const [filter, setFilter] = useState<StagingApprovalQueueFilter>("eligible_for_staging");

  const waveByUnitKey = useMemo(() => {
    const map = new Map<string, NonNullable<BatchQueueLatestWave["items"]>[number]>();
    for (const waveItem of latestWave?.items ?? []) {
      map.set(waveItem.unitKey, waveItem);
    }
    return map;
  }, [latestWave?.items]);

  const rows = useMemo(() => {
    return items
      .map((item) => {
        const eligibility = isStagingWaveSelectable(item);
        const eligibleForStaging = eligibility;
        const metrics = extractDryRunReportMetrics(item.dryRunReport);
        const poiType = presentVamoPoiType(item.category);
        const waveItem = waveByUnitKey.get(item.unitKey);
        return {
          item,
          eligibleForStaging,
          sourceCandidates: metrics?.sourceCandidates ?? null,
          expectedTargetWrites: metrics?.expectedTargetWrites ?? null,
          poiType,
          evidenceStatus: describeStagingQueueEvidenceStatus(item),
          wroteToTarget: item.dryRunReport?.wroteToTarget === false ? "false" : item.dryRunReport ? "invalid" : "—",
          latestWaveLabel: waveItem ? latestWave?.waveKey ?? "—" : "—",
          shipmentId: waveItem?.shipmentId ?? "—",
          blockers: item.blockReasons.length > 0 ? item.blockReasons.join("; ") : waveItem?.blockers.join("; ") || "—",
          nextAction: describeStagingQueueNextAction(item, eligibleForStaging)
        };
      })
      .filter((row) => matchesStagingApprovalQueueFilter(row.item.status, filter, row.eligibleForStaging))
      .sort((a, b) => a.item.runOrder - b.item.runOrder);
  }, [filter, items, latestWave?.waveKey, waveByUnitKey]);

  const selectedSet = useMemo(() => new Set(selectedUnitKeys), [selectedUnitKeys]);
  const selectableRows = rows.filter((row) => row.eligibleForStaging);

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
      <div className="admin-queue-toolbar" role="toolbar" aria-label="Staging verification queue filters">
        {(Object.keys(stagingApprovalQueueFilterLabels) as StagingApprovalQueueFilter[]).map((key) => (
          <button
            key={key}
            type="button"
            className={`admin-queue-filter-chip${filter === key ? " is-active" : ""}`}
            onClick={() => setFilter(key)}
          >
            {stagingApprovalQueueFilterLabels[key]}
          </button>
        ))}
      </div>

      <p className="admin-queue-summary">
        Showing <strong>{rows.length}</strong> scope(s) · selected{" "}
        <strong>{selectedUnitKeys.length}</strong>
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
              <th>POI type</th>
              <th>Status</th>
              <th>Source candidates</th>
              <th>Expected target writes</th>
              <th>wroteToTarget</th>
              <th>Evidence</th>
              <th>Latest verification</th>
              <th>Shipment id</th>
              <th>Blockers</th>
              <th>Next action</th>
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
                    disabled={!row.eligibleForStaging}
                    onChange={() => toggleUnit(row.item.unitKey)}
                  />
                </td>
                <td>{row.item.runOrder}</td>
                <td>
                  <strong>{friendlyUnit(row.item.unitKey)}</strong>
                  <code className="admin-evidence-code">{row.item.unitKey}</code>
                </td>
                <td>
                  <strong>{row.poiType.operatorValue}</strong>
                  <code className="admin-evidence-code">
                    {row.poiType.technicalMapping ?? "No Vamo mapping"}
                  </code>
                </td>
                <td>{queueStatusLabels[row.item.status]}</td>
                <td>{row.sourceCandidates ?? "—"}</td>
                <td>{row.expectedTargetWrites ?? "—"}</td>
                <td>{row.wroteToTarget}</td>
                <td>{row.evidenceStatus}</td>
                <td>
                  <code>{row.latestWaveLabel}</code>
                </td>
                <td>
                  <code>{row.shipmentId}</code>
                </td>
                <td>{row.blockers}</td>
                <td>{row.nextAction}</td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      {rows.length === 0 ? (
        <p className="admin-ux-empty">No scopes match the current staging approval filter.</p>
      ) : null}
    </div>
  );
}
