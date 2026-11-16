param(
  [ValidateSet('Har', 'Hap', 'Tests')][string]$Task = 'Hap',
  [string]$StudioHome = $env:DEVECO_STUDIO_HOME
)
$ErrorActionPreference = 'Stop'
if (-not $StudioHome) { throw 'Set DEVECO_STUDIO_HOME to your DevEco Studio installation directory.' }
$projectRoot = Split-Path -Parent $PSScriptRoot
$env:DEVECO_SDK_HOME = Join-Path $StudioHome 'sdk'
$env:JAVA_HOME = Join-Path $StudioHome 'jbr'
$env:TYPESCRIPT_PATH = Join-Path $StudioHome 'tools/ohpm/node_modules/typescript'
$env:Path = (Join-Path $env:JAVA_HOME 'bin') + ';' + $env:Path
$hvigor = Join-Path $StudioHome 'tools/hvigor/bin/hvigorw.bat'
$ohpm = Join-Path $StudioHome 'tools/ohpm/bin/ohpm.bat'
$bootstrapStarted = $false
$completed = $false
Push-Location $projectRoot
try {
  if ($Task -eq 'Tests') {
    node --test tests/migration.test.cjs
    if ($LASTEXITCODE -ne 0) { throw 'Migration regression tests failed.' }
    return
  }
  # A fresh checkout has no generated HAR. Bootstrap from the source module,
  # then replace only this project's dependency with the packaged artifact.
  node tools/sdk-dependency.cjs source
  if ($LASTEXITCODE -ne 0) { throw 'Cannot select source SDK.' }
  $bootstrapStarted = $true
  & $ohpm install --all
  if ($LASTEXITCODE -ne 0) { throw 'Dependency sync failed.' }
  & $hvigor --mode module -p module=mpsdk@default -p product=default assembleHar --no-daemon
  if ($LASTEXITCODE -ne 0) { throw 'HAR build failed.' }
  New-Item -ItemType Directory -Path 'libs' -Force | Out-Null
  Copy-Item -LiteralPath 'mpsdk/build/default/outputs/default/mpsdk.har' -Destination 'libs/mpsdk.har' -Force
  node tools/sdk-dependency.cjs packaged
  if ($LASTEXITCODE -ne 0) { throw 'Cannot select packaged SDK.' }
  & $ohpm install --all
  if ($LASTEXITCODE -ne 0) { throw 'Packaged HAR dependency sync failed.' }
  if ($Task -eq 'Hap') {
    & $hvigor --mode module -p module=entry@default -p product=default assembleHap --no-daemon
    if ($LASTEXITCODE -ne 0) { throw 'HAP build failed.' }
  }
  $completed = $true
} finally {
  if ($bootstrapStarted -and -not $completed) {
    # A failed bootstrap must never leave the next IDE build using SDK source.
    node tools/sdk-dependency.cjs packaged
    if ((Test-Path -LiteralPath 'libs/mpsdk.har') -and (Test-Path -LiteralPath $ohpm)) {
      & $ohpm install --all
      if ($LASTEXITCODE -ne 0) {
        Write-Warning 'Packaged manifest restored; run OHPM sync before building again.'
      }
    }
  }
  Pop-Location
}
