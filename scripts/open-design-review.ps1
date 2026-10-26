param([string]$Executable)
$ErrorActionPreference = 'Stop'
$taskProject = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
if (-not $Executable) {
  $Executable = Join-Path $taskProject 'build/windows/x64/runner/Release/music_time.exe'
}
$taskExe = Get-Item -LiteralPath $Executable
if (-not $taskExe.VersionInfo.ProductVersion.StartsWith('2.5.1')) {
  throw 'The executable is not the 2.5.1 release build. Build the preview first.'
}
# Explicitly interactive: this window is the review requested by the user.
$taskPreview = Start-Process -FilePath $taskExe.FullName -ArgumentList '--design-preview' -WorkingDirectory $taskExe.DirectoryName -WindowStyle Normal -PassThru
[pscustomobject]@{
  ProcessId = $taskPreview.Id
  Executable = $taskExe.FullName
  TemporaryProfile = Join-Path $env:TEMP 'music_time_design_review_1_3'
  Installed = $false
}
