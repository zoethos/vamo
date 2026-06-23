import type { Metadata } from "next";
import Image from "next/image";
import Link from "next/link";
import {
  providerDashboardGuardrails,
  providerDashboardServices,
  providerDashboardSignals,
} from "@/content/provider-dashboard";

export const metadata: Metadata = {
  title: "Provider dashboard · Vamo",
  robots: {
    index: false,
    follow: false,
  },
};

const statusLabels = {
  live: "Live",
  planned: "Planned",
  watch: "Watch",
};

export default function ProviderDashboardPage() {
  return (
    <main className="provider-dashboard">
      <nav className="provider-masthead" aria-label="Provider dashboard">
        <Link className="provider-brand" href="/">
          <Image
            src="/brand/mark_white.png"
            alt=""
            width={34}
            height={34}
            priority
          />
          <span>Vamo</span>
        </Link>
        <span className="provider-product-label">Provider Control Plane</span>
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
            <Image
              src="/brand/mark_white.png"
              alt=""
              width={52}
              height={52}
            />
          </div>
          <span>Next unlock</span>
          <strong>Live usage after admin auth</strong>
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
