import Image from "next/image";

export default function HomePage() {
  return (
    <main className="landing">
      <Image
        src="/brand/journey_mark.png"
        alt="Vamo mark"
        width={320}
        height={320}
        className="landing-mark"
        priority
      />
      <h1 className="landing-wordmark">VAMO</h1>
      <p className="landing-tagline">Si va?</p>
      <p className="landing-soon">Coming to Google Play</p>
    </main>
  );
}
