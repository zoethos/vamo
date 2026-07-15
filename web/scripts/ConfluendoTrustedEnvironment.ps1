function Read-ConfluendoTrustedEnvironmentFile {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory = $true)]
    [string]$Path,

    [Parameter(Mandatory = $true)]
    [string[]]$AllowedNames
  )

  if (!(Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "Missing trusted worker environment file: $Path"
  }

  $allowed = @{}
  foreach ($name in $AllowedNames) {
    $allowed[$name] = $true
  }
  $values = @{}

  foreach ($line in Get-Content -LiteralPath $Path) {
    $trimmed = $line.Trim()
    if (!$trimmed -or $trimmed.StartsWith("#")) {
      continue
    }
    if ($trimmed -notmatch "^(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$") {
      continue
    }

    $name = $Matches[1]
    if (!$allowed.ContainsKey($name)) {
      continue
    }
    if ($values.ContainsKey($name)) {
      throw "Duplicate trusted worker environment entry for $name in $Path."
    }

    $value = $Matches[2].Trim()
    if ($value.Length -ge 2 -and (
      ($value.StartsWith('"') -and $value.EndsWith('"')) -or
      ($value.StartsWith("'") -and $value.EndsWith("'"))
    )) {
      $value = $value.Substring(1, $value.Length - 2)
    }
    $values[$name] = $value
  }

  return $values
}
