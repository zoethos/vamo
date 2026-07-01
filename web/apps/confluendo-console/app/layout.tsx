import type { Metadata } from "next";
import { IBM_Plex_Mono, Schibsted_Grotesk } from "next/font/google";
import Link from "next/link";
import "./globals.css";

// Confluendo platform typefaces. Exposed as CSS variables and applied only to
// the platform-owned admin/auth surfaces; the Vamo consumer pages keep the
// system stack.
const confluendoDisplay = Schibsted_Grotesk({
  subsets: ["latin"],
  weight: ["400", "500", "600", "700"],
  variable: "--font-confluendo",
  display: "swap",
});

const confluendoMono = IBM_Plex_Mono({
  subsets: ["latin"],
  weight: ["400", "500"],
  variable: "--font-confluendo-mono",
  display: "swap",
});

export const metadata: Metadata = {
  title: "Confluendo Console",
  description: "Operator console for governed ingestion and delivery.",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en" className={`${confluendoDisplay.variable} ${confluendoMono.variable}`}>
      <body>
        <div className="site-shell">
          {children}
          <footer className="site-footer">
            <Link href="/privacy">Privacy</Link>
            <Link href="/terms">Terms</Link>
            <Link href="mailto:hello@confluendo.com">hello@confluendo.com</Link>
          </footer>
        </div>
      </body>
    </html>
  );
}
