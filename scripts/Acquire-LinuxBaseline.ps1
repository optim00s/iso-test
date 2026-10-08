#requires -version 5.1
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$config=Get-Content (Join-Path $root 'config\linux-baseline.json') -Raw | ConvertFrom-Json
$dest=Join-Path $root 'assets\linux\baseline'
New-Item -ItemType Directory -Path $dest -Force | Out-Null
[Net.ServicePointManager]::SecurityProtocol=[Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
$uvUrl="https://github.com/astral-sh/uv/releases/download/$($config.uvVersion)/$($config.uvArchive)"
$sum=Invoke-WebRequest -Uri ($uvUrl+'.sha256') -UseBasicParsing
# GitHub release assets use application/octet-stream, so PowerShell can return byte[].
$sumText=if ($sum.Content -is [byte[]]) { [Text.Encoding]::UTF8.GetString($sum.Content) } else { [string]$sum.Content }
$sumText=$sumText.TrimStart([char]0xfeff).Trim()
$sumPattern='\A([0-9a-fA-F]{64})(?:[ \t]+\*?' + [regex]::Escape($config.uvArchive) + ')?\z'
if ($sumText -notmatch $sumPattern) { throw 'Cannot parse the official uv SHA256.' }
$uvHash=$Matches[1].ToLowerInvariant()
$files=@(
  @{Name=$config.uvArchive;Uri=$uvUrl;Hash=$uvHash},
  @{Name=$config.anacondaInstaller;Uri=$config.anacondaUrl;Hash=$config.anacondaSha256}
)
$lines=foreach($file in $files) {
  $path=Join-Path $dest $file.Name
  $partial=$path+'.partial'
  try {
    $candidate=$path
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
      Invoke-WebRequest -Uri $file.Uri -OutFile $partial -UseBasicParsing
      $candidate=$partial
    }
    $hash=(Get-FileHash -LiteralPath $candidate -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($hash -ne $file.Hash) { throw "SHA256 mismatch: $($file.Name)" }
    if ($candidate -eq $partial) { Move-Item -LiteralPath $partial -Destination $path }
    Write-Host "PASS: $($file.Name) $hash"
    "$hash  $($file.Name)"
  } finally { if(Test-Path -LiteralPath $partial){ Remove-Item -LiteralPath $partial -Force } }
}
# GNU sha256sum treats a CR in a CRLF manifest as part of the filename.
[IO.File]::WriteAllText((Join-Path $dest 'SHA256SUMS'), (($lines -join "`n") + "`n"), (New-Object Text.UTF8Encoding($false)))
