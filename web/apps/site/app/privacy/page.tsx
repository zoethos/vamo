import Link from "next/link";
import {
  privacyIntro,
  privacyMeta,
  privacySections,
} from "@/content/privacy-content";

function renderInline(text: string) {
  const parts = text.split(/(\*\*[^*]+\*\*)/g);
  return parts.map((part, i) => {
    if (part.startsWith("**") && part.endsWith("**")) {
      return <strong key={i}>{part.slice(2, -2)}</strong>;
    }
    return part;
  });
}

export default function PrivacyPage() {
  return (
    <main className="site-main prose">
      <h1>Privacy Policy</h1>
      <p>
        <em>{privacyMeta}</em>
      </p>
      <p>{renderInline(privacyIntro)}</p>
      {privacySections.map((section) => (
        <section key={section.title}>
          <h2>{section.title}</h2>
          {"paragraphs" in section &&
            section.paragraphs?.map((p) => (
              <p key={p.slice(0, 24)}>{renderInline(p)}</p>
            ))}
          {"list" in section && section.list && (
            <ul>
              {section.list.map((item) => (
                <li key={item}>{renderInline(item)}</li>
              ))}
            </ul>
          )}
          {"footer" in section && section.footer && <p>{section.footer}</p>}
        </section>
      ))}
      <p>
        <Link href="/">Back home</Link>
      </p>
    </main>
  );
}
