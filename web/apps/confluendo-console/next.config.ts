import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  reactStrictMode: true,
  outputFileTracingIncludes: {
    "/*": [
      "../../packages/ingestion-platform/fixtures/imported/vamo-place-intelligence/manifest.yaml"
    ]
  }
};

export default nextConfig;
