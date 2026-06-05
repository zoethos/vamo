import Image from "next/image";

export default function HomePage() {
  return (
    <main className="landing">
      <Image
        src="/brand/mark_white.png"
        alt="Vamo mark"
        width={120}
        height={120}
        className="landing-mark"
        priority
      />
      <h1 className="landing-wordmark">VAMO</h1>
      <p className="landing-tagline">Si va?</p>
      <p className="landing-soon">Coming to Google Play</p>
    </main>
  );
}
