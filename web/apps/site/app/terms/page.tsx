import Link from "next/link";

export default function TermsPage() {
  return (
    <main className="site-main prose">
      <h1>
        Terms of Service
        <span className="draft-badge">Draft</span>
      </h1>
      <p>
        <em>Last updated: June 2026 · Contact: hello@vamo.world</em>
      </p>
      <p>
        Vamo is provided for personal, non-commercial use among friends and
        travel companions. You are responsible for the trip data you create and
        share with your group.
      </p>
      <h2>No warranty</h2>
      <p>
        The service is provided &quot;as is&quot; without warranties of any kind.
        We do not move money, provide financial advice, or guarantee that
        balances or splits are legally binding.
      </p>
      <h2>EU law</h2>
      <p>
        These terms are governed by the laws of Italy and applicable European
        Union regulations, without prejudice to mandatory consumer protections
        in your country of residence.
      </p>
      <h2>Contact</h2>
      <p>
        Questions:{" "}
        <a href="mailto:hello@vamo.world">hello@vamo.world</a>
      </p>
      <p>
        <Link href="/">Back home</Link>
      </p>
    </main>
  );
}
