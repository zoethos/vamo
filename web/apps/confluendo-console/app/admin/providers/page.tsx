import type { Metadata } from "next";
import Link from "next/link";
import { STAGING_CANARY_FRESH_STEP_UP_WINDOW_MS } from "@confluendo/ingestion-platform/core";
import { AdminSessionActions } from "@/app/admin/admin-session-actions";
import { ConfluendoMark } from "@/app/admin/confluendo-brand";
import { DashboardThemeToggle } from "@/app/admin/dashboard-theme-toggle";
import {
  providerDashboardGuardrails,
  providerDashboardServices,
  providerDashboardSignals,
} from "@/content/provider-dashboard";
import { requireIngestionDashboardAccess } from "@/lib/ingestion-admin-auth";

export const metadata: Metadata = {
  title: "Provider control · Confluendo",
  robots: {
    index: false,
    follow: false,
  },
};

export const dynamic = "force-dynamic";

const statusLabels = {
  live: "Live",
  planned: "Planned",
  watch: "Watch",
};

export default async function ProviderDashboardPage() {
  const principal = await requireIngestionDashboardAccess({
    projectKey: "vamo",
    nextPath: "/admin/providers",
  });
  const serverNowMs = Date.now();
  const freshStepUpExpiresAt = freshStepUpExpiry(principal.stepUpSatisfiedAt);

  return (
    <main
      className="provider-dashboard"
      data-theme="dark"
      id="provider-dashboard-theme-root"
    >
      <nav className="provider-masthead admin-masthead" aria-label="Provider dashboard">
        <Link className="provider-brand" href="/admin/ingestion">
          <ConfluendoMark className="provider-brand-mark" size={34} />
          <span>Confluendo</span>
        </Link>
        <div className="admin-masthead-controls">
          <div className="admin-nav admin-nav-dark" aria-label="Admin sections">
            <Link
              className="admin-nav-link admin-nav-link-active"
              href="/admin/providers"
            >
              Providers
            </Link>
            <Link className="admin-nav-link" href="/admin/ingestion">
              Ingestion
            </Link>
          </div>
          <Link className="admin-help-placeholder" href="/admin/help#providers">
            <span aria-hidden="true" className="admin-help-placeholder-icon">
              ?
            </span>
            Help
          </Link>
          <AdminSessionActions
            principal={principal}
            freshStepUpExpiresAt={freshStepUpExpiresAt}
            mfaChallengeHref="/admin/mfa/challenge?reason=fresh_step_up_required&next=%2Fadmin%2Fproviders"
            serverNowMs={serverNowMs}
          />
          <DashboardThemeToggle
            defaultTheme="dark"
            label="Provider dashboard theme"
            rootId="provider-dashboard-theme-root"
            storageKey="confluendo-provider-dashboard-theme"
          />
        </div>
      </nav>
      <section className="provider-hero">
        <div>
          <p className="provider-eyebrow">Founder dashboard · P0</p>
          <h1>Provider control</h1>
          <p>
            A read-only view of the services that can cost money, throttle, or
            degrade the app. P0 is a safe shell: no secrets, no service-role
            reads, no switches.
          </p>
        </div>
        <div className="provider-hero-card">
          <div className="provider-card-mark">
            <ConfluendoMark size={52} />
          </div>
          <span>Next unlock</span>
          <strong>
            {principal.role} · {principal.assuranceLevel}
          </strong>
          <p>
            The control-plane tables are intentionally private. P1 adds a
            server-only admin boundary before live data appears here.
          </p>
        </div>
      </section>

      <section className="provider-signal-grid" aria-label="Dashboard signals">
        {providerDashboardSignals.map((signal) => (
          <div
            className={`provider-signal provider-signal-${signal.tone}`}
            key={signal.label}
          >
            <span>{signal.label}</span>
            <strong>{signal.value}</strong>
          </div>
        ))}
      </section>

      <section className="provider-section">
        <div className="provider-section-heading">
          <p className="provider-eyebrow">Services</p>
          <h2>External dependency watchlist</h2>
        </div>
        <div className="provider-service-grid">
          {providerDashboardServices.map((service) => (
            <article className="provider-service-card" key={service.service}>
              <div className="provider-service-topline">
                <h3>{service.service}</h3>
                <span className={`provider-status provider-status-${service.status}`}>
                  {statusLabels[service.status]}
                </span>
              </div>
              <p>{service.purpose}</p>
              <dl>
                <div>
                  <dt>Providers</dt>
                  <dd>{service.providers.join(" -> ")}</dd>
                </div>
                <div>
                  <dt>Cap</dt>
                  <dd>{service.freeCapLabel}</dd>
                </div>
                <div>
                  <dt>Cache</dt>
                  <dd>{service.cachePolicy}</dd>
                </div>
                <div>
                  <dt>Next</dt>
                  <dd>{service.nextStep}</dd>
                </div>
              </dl>
            </article>
          ))}
        </div>
      </section>

      <section className="provider-section provider-guardrail-panel">
        <div>
          <p className="provider-eyebrow">Guardrails</p>
          <h2>Safe before powerful</h2>
          <p>
            This dashboard starts as a flight board, not a control console.
            Editing caps, switching providers, and kill switches come only after
            admin auth, audit logging, and rollback paths are in place.
          </p>
        </div>
        <ul>
          {providerDashboardGuardrails.map((guardrail) => (
            <li key={guardrail}>{guardrail}</li>
          ))}
        </ul>
      </section>

      <p className="provider-backlink">
        <Link href="/">Back to Vamo</Link>
      </p>
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
