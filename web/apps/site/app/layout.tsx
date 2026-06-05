import type { Metadata } from "next";
import Link from "next/link";
import "./globals.css";

export const metadata: Metadata = {
  title: "Vamo",
  description: "Si va? Split trips, capture moments, share the story.",
};

export default function RootLayout({
  children,
}: Readonly<{
  children: React.ReactNode;
}>) {
  return (
    <html lang="en">
      <body>
        <div className="site-shell">
          {children}
          <footer className="site-footer">
            <Link href="/privacy">Privacy</Link>
            <Link href="/terms">Terms</Link>
            <Link href="mailto:hello@vamo.world">hello@vamo.world</Link>
          </footer>
        </div>
      </body>
    </html>
  );
}
