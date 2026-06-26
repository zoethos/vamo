export interface SourceConnectionViolation {
  path: string;
  message: string;
}

const forbiddenSnapshotConnectionKeys = new Set([
  "url",
  "endpoint",
  "httpurl",
  "httpsurl",
  "apiurl",
  "baseurl",
  "downloadurl",
  "proxy",
  "proxyurl",
  "httpproxy",
  "httpsproxy",
  "socks",
  "socksproxy",
  "tor",
  "vpn",
  "vpnprofile",
  "residential",
  "residentialproxy",
  "iprotation",
  "rotateip",
  "headers",
  "authorization",
  "cookie",
  "cookies",
  "rotateuseragent",
  "useragentpool"
]);

export function findLocalSnapshotConnectionViolations(
  connection: Record<string, unknown> | undefined,
  options: {
    pathPrefix?: string;
    requireSnapshotPath?: boolean;
  } = {}
): SourceConnectionViolation[] {
  const pathPrefix = options.pathPrefix ?? "source.connection";
  const violations: SourceConnectionViolation[] = [];
  const snapshotPath = connection?.snapshotPath ?? connection?.path;

  if (
    options.requireSnapshotPath &&
    !(typeof snapshotPath === "string" && snapshotPath.trim().length > 0)
  ) {
    violations.push({
      path: `${pathPrefix}.snapshotPath`,
      message: "Snapshot source requires source.connection.snapshotPath or source.connection.path."
    });
  }

  if (typeof snapshotPath === "string" && looksLikeUrl(snapshotPath)) {
    const pathKey = typeof connection?.snapshotPath === "string" ? "snapshotPath" : "path";
    violations.push({
      path: `${pathPrefix}.${pathKey}`,
      message: "Snapshot source only reads local files; URL inputs are not allowed."
    });
  }

  for (const key of Object.keys(connection ?? {})) {
    if (forbiddenSnapshotConnectionKeys.has(normalizeConnectionKey(key))) {
      violations.push({
        path: `${pathPrefix}.${key}`,
        message: `Snapshot source does not allow network/evasion connection field: ${key}`
      });
    }
  }

  return violations;
}

function looksLikeUrl(value: string): boolean {
  return /^[a-z][a-z0-9+.-]*:\/\//i.test(value);
}

function normalizeConnectionKey(key: string): string {
  return key.replace(/[_-]/g, "").toLowerCase();
}
