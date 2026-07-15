import type { Metadata } from "next";
import Link from "next/link";
import { STAGING_CANARY_FRESH_STEP_UP_WINDOW_MS } from "@confluendo/ingestion-platform/core";
import { AdminSessionActions } from "@/app/admin/admin-session-actions";
import { ConfluendoMark } from "@/app/admin/confluendo-brand";
import { DashboardThemeToggle } from "@/app/admin/dashboard-theme-toggle";
import { requireIngestionDashboardAccess } from "@/lib/ingestion-admin-auth";

export const metadata: Metadata = {
  title: "Operations manual · Confluendo",
  robots: {
    index: false,
    follow: false
  }
};

export const dynamic = "force-dynamic";

type HelpSection = {
  id:
    | "lifecycle"
    | "access"
    | "queue"
    | "automation"
    | "verification"
    | "delivery"
    | "providers"
    | "troubleshooting"
    | "glossary";
  eyebrow: string;
  title: string;
  paragraphs: readonly string[];
  terms: ReadonlyArray<{ term: string; definition: string }>;
};

const helpSections: readonly HelpSection[] = [
  {
    id: "lifecycle",
    eyebrow: "Reference",
    title: "The ingestion lifecycle",
    paragraphs: [
      "Every scope follows the same path: Queue, Simulate, Verify in staging, Prepare delivery, then Apply in Vamo. The workflow navigator shows the live portfolio position; this manual explains the operating meaning behind each step.",
      "Confluendo owns planning, simulation, staging verification, and consumer-inbox delivery. Vamo owns the final product-table apply. A delivered package is not yet product data."
    ],
    terms: [
      { term: "Scope", definition: "One geography and POI-type unit of work, such as Paris · Landmark." },
      { term: "Simulate", definition: "A dry-run that proves the planned write without touching a target." },
      { term: "Verify", definition: "Consumer-shaped writes exercised against Vamo staging only." },
      { term: "Apply", definition: "Vamo's gated operation that writes approved inbox data into Vamo product tables." }
    ]
  },
  {
    id: "access",
    eyebrow: "Reference",
    title: "Access and MFA",
    paragraphs: [
      "The console is available only to allowlisted operators. Read-only status can be viewed with the current signed-in session; protected approvals and apply actions require the role and MFA level shown in the masthead.",
      "A short MFA window protects high-impact actions. When it expires, refresh MFA and return to the same operation. The console never treats an expired window as approval."
    ],
    terms: [
      { term: "Admin", definition: "The current highest operator role. It can request gated actions but cannot bypass policy." },
      { term: "AAL2", definition: "A verified second authentication factor is present for the signed-in session." },
      { term: "MFA window", definition: "The short-lived fresh verification period required for protected actions." }
    ]
  },
  {
    id: "queue",
    eyebrow: "Reference",
    title: "Queue and scope statuses",
    paragraphs: [
      "The queue is organized by scope, not raw records. Use the table filters to understand all scopes, then open an individual scope when its evidence trail matters.",
      "A parked scope is waiting for source snapshot coverage and is not an operator exception. A blocked scope has evidence or compatibility that needs investigation before it can advance."
    ],
    terms: [
      { term: "Ready to simulate", definition: "A source-backed scope can enter the bounded simulation path." },
      { term: "Parked", definition: "No matching data is present in the approved source snapshot yet." },
      { term: "Blocked", definition: "Evidence, policy, or target compatibility needs review before retry." }
    ]
  },
  {
    id: "automation",
    eyebrow: "Reference",
    title: "Automation and policy limits",
    paragraphs: [
      "Automation advances one bounded step at a time inside the active policy. Preview shows the next selection without changing data; execution records the action in the control plane.",
      "Ramp changes widen or reduce cycle limits within the owner ceiling. They do not bypass staging verification, production package approval, production delivery confirmation, or Vamo apply controls."
    ],
    terms: [
      { term: "Policy", definition: "The approved operating envelope: allowed source, queue plan, limits, and transitions." },
      { term: "Ramp", definition: "The current bounded volume profile within the owner-approved ceiling." },
      { term: "Preview", definition: "A non-writing evaluation of the next safe automation action." }
    ]
  },
  {
    id: "verification",
    eyebrow: "Reference",
    title: "Verification in staging",
    paragraphs: [
      "Simulation proves a plan without writes. Staging verification then exercises consumer-shaped writes against the staging target and records the evidence needed for package approval.",
      "If staging verification is blocked, investigate the evidence, correct the source or target mismatch, and re-run the bounded verification. Do not widen the batch while the evidence is unclean."
    ],
    terms: [
      { term: "Expected target writes", definition: "The number of canonical and reference writes the verified scope is expected to produce." },
      { term: "Staging verified", definition: "The target accepted the bounded consumer-shaped write and the evidence is valid." },
      { term: "Compatibility", definition: "Whether a source POI type can be mapped safely to the Vamo consumer contract." }
    ]
  },
  {
    id: "delivery",
    eyebrow: "Reference",
    title: "Delivery and consumer apply",
    paragraphs: [
      "Package approval groups staging-verified scopes into a bounded delivery wave. Delivery writes only to the Vamo consumer inbox after explicit confirmation. It never applies directly to Vamo product tables.",
      "After delivery, refresh apply telemetry before deciding what happens next. A batch apply is sequential: if it stops partway through, inspect the visible package states, keep the completed packages as completed, and retry only the remaining eligible packages."
    ],
    terms: [
      { term: "Eligible for package", definition: "Staging evidence is valid and the scope is not already spent by another package wave." },
      { term: "Delivered to inbox", definition: "A verified package reached the Vamo consumer inbox; Vamo has not necessarily applied it." },
      { term: "Apply pending", definition: "The package is in the consumer inbox and awaits the operator-controlled Vamo apply action." },
      { term: "Apply state unknown", definition: "Telemetry is unavailable. Refresh it before assuming success or failure." }
    ]
  },
  {
    id: "providers",
    eyebrow: "Reference",
    title: "Providers and source releases",
    paragraphs: [
      "Provider control governs source access, acquisition rights, snapshot releases, attribution, and retention. Source releases are prepared before scopes enter the queue.",
      "A source release must be verified and registered before it is activated for a consumer plan. Live provider credentials stay at the source boundary and are never exposed in the browser."
    ],
    terms: [
      { term: "Snapshot release", definition: "A versioned, verified local data artifact with provenance, checksum, attribution, and retention facts." },
      { term: "Activation ready", definition: "A registered release passed intake checks and can be deliberately bound to a consumer plan." },
      { term: "Attribution", definition: "The source credit required when using approved factual place data." }
    ]
  },
  {
    id: "troubleshooting",
    eyebrow: "Reference · recovery",
    title: "Troubleshooting and recovery",
    paragraphs: [
      "Use Diagnostics for actionable exceptions and the Scope context rail for a single scope's evidence trail. Parked empty-source scopes are supply gaps, not incidents.",
      "When a delivery or apply action is uncertain, refresh the control-plane and consumer telemetry first. Idempotent package identifiers and checksums make safe reconciliation possible; do not create duplicate packages to compensate for an unknown state."
    ],
    terms: [
      { term: "Stale approval", definition: "The short approval window passed before execution. Re-approve the scope; do not reuse expired approval." },
      { term: "Checksum mismatch", definition: "The proposed package content differs from the recorded content and is refused before a duplicate write." },
      { term: "Evidence trail", definition: "The recorded simulation, staging, delivery, and consumer-apply states for one scope." }
    ]
  },
  {
    id: "glossary",
    eyebrow: "Reference",
    title: "Glossary",
    paragraphs: [
      "The console uses operator language first. Technical keys remain available as secondary evidence when an operator needs to trace a source record, package, or audit event."
    ],
    terms: [
      { term: "Wave", definition: "A bounded set of scopes approved together for staging or consumer-inbox delivery." },
      { term: "Package", definition: "The verified deliverable written to the consumer inbox." },
      { term: "Audit reason", definition: "The operator's durable explanation for requesting a protected action." }
    ]
  }
];

const workflowSteps = [
  ["Queue", "Source-backed scopes are ready, parked, or blocked."],
  ["Simulate", "Prove the plan with no target writes."],
  ["Verify in staging", "Exercise bounded consumer-shaped writes."],
  ["Prepare delivery", "Approve and deliver verified inbox packages."],
  ["Apply in Vamo", "Vamo applies consumer-approved data to product tables."]
] as const;

export default async function HelpCenterPage() {
  const principal = await requireIngestionDashboardAccess({
    projectKey: "vamo",
    nextPath: "/admin/help"
  });
  const serverNowMs = Date.now();
  const freshStepUpExpiresAt = freshStepUpExpiry(principal.stepUpSatisfiedAt);

  return (
    <main className="admin-console provider-dashboard admin-help-page" data-theme="dark" id="help-center-theme-root">
      <nav className="provider-masthead admin-masthead" aria-label="Admin dashboard">
        <Link className="provider-brand admin-brand" href="/admin/ingestion">
          <ConfluendoMark className="provider-brand-mark" size={34} />
          <span>Confluendo</span>
        </Link>
        <div className="admin-masthead-controls">
          <div className="admin-product-switch" aria-label="Confluendo products">
            <Link className="admin-product-switch-link" href="/admin/providers">
              Providers
            </Link>
            <Link className="admin-product-switch-link" href="/admin/ingestion">
              Ingestion
            </Link>
          </div>
          <Link aria-current="page" className="admin-help-placeholder admin-help-link-active" href="#lifecycle">
            <span aria-hidden="true" className="admin-help-placeholder-icon">
              ?
            </span>
            Help
          </Link>
          <AdminSessionActions
            principal={principal}
            freshStepUpExpiresAt={freshStepUpExpiresAt}
            mfaChallengeHref="/admin/mfa/challenge?reason=fresh_step_up_required&next=%2Fadmin%2Fhelp"
            serverNowMs={serverNowMs}
          />
          <DashboardThemeToggle
            defaultTheme="dark"
            label="Help center theme"
            rootId="help-center-theme-root"
            storageKey="confluendo-help-center-theme"
          />
        </div>
      </nav>

      <header className="admin-help-heading">
        <div>
          <p className="admin-help-eyebrow">Confluendo operations manual</p>
          <h1>Operate the ingestion lifecycle with confidence.</h1>
          <p>
            Reference guidance for the live console. The workflow navigator answers where work is now;
            this page explains what each state means and the safe route forward.
          </p>
        </div>
        <Link className="admin-help-return" href="/admin/ingestion">
          Return to ingestion
        </Link>
      </header>

      <section className="admin-help-lifecycle" aria-labelledby="help-lifecycle-title">
        <div className="admin-help-section-heading">
          <p className="admin-help-eyebrow">Workflow</p>
          <h2 id="help-lifecycle-title">One direction, two owners</h2>
          <p>Confluendo prepares and delivers. Vamo controls product-table apply.</p>
        </div>
        <ol className="admin-help-workflow-steps">
          {workflowSteps.map(([label, detail], index) => (
            <li key={label}>
              <span className="admin-help-workflow-index">{index + 1}</span>
              <strong>{label}</strong>
              <p>{detail}</p>
            </li>
          ))}
        </ol>
      </section>

      <div className="admin-help-layout">
        <aside className="admin-help-toc" aria-label="Operations manual sections">
          <span className="admin-help-toc-label">On this page</span>
          <nav>
            {helpSections.map((section) => (
              <a href={`#${section.id}`} key={section.id}>
                {section.title}
              </a>
            ))}
          </nav>
        </aside>

        <div className="admin-help-sections">
          {helpSections.map((section) => (
            <section className="admin-help-reference-section" id={section.id} key={section.id}>
              <p className="admin-help-eyebrow">{section.eyebrow}</p>
              <h2>{section.title}</h2>
              {section.paragraphs.map((paragraph) => (
                <p key={paragraph}>{paragraph}</p>
              ))}
              <dl>
                {section.terms.map((entry) => (
                  <div key={entry.term}>
                    <dt>{entry.term}</dt>
                    <dd>{entry.definition}</dd>
                  </div>
                ))}
              </dl>
            </section>
          ))}
        </div>
      </div>
    </main>
  );
}

function freshStepUpExpiry(stepUpSatisfiedAt: string | undefined): string | undefined {
  if (!stepUpSatisfiedAt) {
    return undefined;
  }
  const satisfiedMs = Date.parse(stepUpSatisfiedAt);
  if (!Number.isFinite(satisfiedMs)) {
    return undefined;
  }
  return new Date(satisfiedMs + STAGING_CANARY_FRESH_STEP_UP_WINDOW_MS).toISOString();
}
