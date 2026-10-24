param([string]$Executable)
$ErrorActionPreference = 'Stop'
$taskProject = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if (-not $Executable) {
  $Executable = Join-Path $taskProject 'build/review-2.0.0/music_time.exe'
}
$taskExe = Get-Item -LiteralPath $Executable
if (-not $taskExe.VersionInfo.ProductVersion.StartsWith('2.0.0')) {
  throw 'The executable is not the 2.0.0 design review build. Build the preview first.'
}
# Explicitly interactive: this window is the review requested by the user.
$taskPreview = Start-Process -FilePath $taskExe.FullName -ArgumentList '--design-preview' -WorkingDirectory $taskExe.DirectoryName -WindowStyle Normal -PassThru
[pscustomobject]@{
  ProcessId = $taskPreview.Id
  Executable = $taskExe.FullName
  TemporaryProfile = Join-Path $env:TEMP 'music_time_design_review_1_3'
  Installed = $false
}
