import assert from "node:assert/strict";
import test from "node:test";
import { findSharpReachabilityViolations } from "./osv-sharp-reachability-guard.mjs";

const safeInputs = {
  configFiles: [
    { path: "web/apps/site/next.config.ts", content: "export default { reactStrictMode: true };" }
  ],
  sourceFiles: [
    {
      path: "web/apps/site/app/page.tsx",
      content: 'import Image from "next/image"; export const Page = () => <Image src="/brand/mark_white.png" alt="Vamo" />;'
    }
  ],
  manifests: [
    { path: "web/apps/site/package.json", packageJson: { dependencies: { next: "^15.1.0" } } }
  ]
};

test("permits only fixed local brand images with no direct sharp dependency", () => {
  assert.deepEqual(findSharpReachabilityViolations(safeInputs), []);
});

test("rejects remote image configuration", () => {
  const violations = findSharpReachabilityViolations({
    ...safeInputs,
    configFiles: [{ path: "web/apps/site/next.config.ts", content: "images: { remotePatterns: [] }" }]
  });

  assert.match(violations.join("\n"), /remote Next Image configuration/);
});

test("rejects dynamic image sources and console image optimization", () => {
  const violations = findSharpReachabilityViolations({
    ...safeInputs,
    sourceFiles: [
      {
        path: "web/apps/site/app/page.tsx",
        content: 'import Image from "next/image"; export const Page = ({ source }) => <Image src={source} alt="Vamo" />;'
      },
      {
        path: "web/apps/confluendo-console/app/page.tsx",
        content: 'import Image from "next/image"; export const Page = () => <Image src="/brand/mark_white.png" alt="Confluendo" />;'
      }
    ]
  });

  assert.match(violations.join("\n"), /fixed local \/brand assets/);
  assert.match(violations.join("\n"), /only the public site may import next\/image/);
});

test("rejects direct sharp dependencies", () => {
  const violations = findSharpReachabilityViolations({
    ...safeInputs,
    manifests: [{ path: "web/package.json", packageJson: { dependencies: { sharp: "^0.35.0" } } }]
  });

  assert.match(violations.join("\n"), /direct sharp dependencies/);
});
