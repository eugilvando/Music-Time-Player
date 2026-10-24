param([Parameter(Mandatory=$true)][string]$Executable)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Runtime.WindowsRuntime
$null=[Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager, Windows.Media.Control, ContentType=WindowsRuntime]
function Await-WinRt($operation,[Type]$resultType) {
  $method=[System.WindowsRuntimeSystemExtensions].GetMethods() | Where-Object { $_.Name -eq 'AsTask' -and $_.IsGenericMethod -and $_.GetParameters().Count -eq 1 -and $_.GetParameters()[0].ParameterType.Name -eq 'IAsyncOperation`1' } | Select-Object -First 1
  $task=$method.MakeGenericMethod($resultType).Invoke($null,@($operation))
  if (-not $task.Wait(10000)) { throw 'WinRT timeout' }
  return $task.Result
}
$folder=Join-Path $env:TEMP 'music_time_validation_profile'
New-Item -ItemType Directory -Force -Path $folder | Out-Null
$wav=Join-Path $folder 'windows-controls.wav'
$writer=[IO.BinaryWriter]::new([IO.File]::Create($wav))
$size=8000*2*120
try {
  $writer.Write([Text.Encoding]::ASCII.GetBytes('RIFF')); $writer.Write([int](36+$size))
  $writer.Write([Text.Encoding]::ASCII.GetBytes('WAVEfmt ')); $writer.Write([int]16)
  $writer.Write([int16]1); $writer.Write([int16]1); $writer.Write([int]8000); $writer.Write([int]16000)
  $writer.Write([int16]2); $writer.Write([int16]16); $writer.Write([Text.Encoding]::ASCII.GetBytes('data'))
  $writer.Write([int]$size); $writer.Write([byte[]]::new($size))
} finally { $writer.Dispose() }
$logFile=Join-Path $folder 'windows_diagnostics.log'
$previousLines=if (Test-Path $logFile) { @(Get-Content $logFile).Count } else { 0 }
[IO.File]::WriteAllText((Join-Path $folder 'windows-controls.lrc'), "[00:00.00]Validação local do Music Time"+[Environment]::NewLine+"[00:02.00]Troca de estilo com a mesma sessão")
$native=Start-Process -FilePath $Executable -ArgumentList @('--validation-profile', ('--smoke-audio='+$wav)) -WindowStyle Hidden -PassThru
try {
  Start-Sleep -Seconds 4
  if ($native.HasExited) { throw ('App exited: '+$native.ExitCode) }
  $manager=Await-WinRt ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager]::RequestAsync()) ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionManager])
  $session=$manager.GetSessions() | Where-Object { $_.SourceAppUserModelId -eq 'MusicTime.Desktop.Validation' } | Select-Object -First 1
  if (-not $session) { throw 'Validation media session missing' }
  'Session: '+$session.SourceAppUserModelId
  $mediaProperties = Await-WinRt ($session.TryGetMediaPropertiesAsync()) ([Windows.Media.Control.GlobalSystemMediaTransportControlsSessionMediaProperties, Windows.Media.Control, ContentType=WindowsRuntime])
  if (-not $mediaProperties.Thumbnail) { throw 'Windows artwork missing' }
  $thumbnailStream = Await-WinRt ($mediaProperties.Thumbnail.OpenReadAsync()) ([Windows.Storage.Streams.IRandomAccessStreamWithContentType, Windows.Storage.Streams, ContentType=WindowsRuntime])
  try {
    $streamType = [Windows.Storage.Streams.IRandomAccessStream, Windows.Storage.Streams, ContentType=WindowsRuntime]
    $thumbnailSize = $streamType.GetProperty('Size').GetValue($thumbnailStream, $null)
    if ($null -eq $thumbnailSize -or $thumbnailSize -eq 0) { throw 'Windows artwork empty' }
    'Windows artwork: OK ('+$thumbnailSize+' bytes)'
  } finally { [System.Runtime.InteropServices.Marshal]::ReleaseComObject($thumbnailStream) | Out-Null }
  if (-not (Await-WinRt ($session.TryPauseAsync()) ([bool]))) { throw 'Pause rejected' }
  Start-Sleep -Milliseconds 800
  if ($session.GetPlaybackInfo().PlaybackStatus.ToString() -ne 'Paused') { throw 'Pause state missing' }
  'Windows pause: OK'
  if (-not (Await-WinRt ($session.TryPlayAsync()) ([bool]))) { throw 'Play rejected' }
  Start-Sleep -Milliseconds 800
  if ($session.GetPlaybackInfo().PlaybackStatus.ToString() -ne 'Playing') { throw 'Play state missing' }
  'Windows play: OK'
  $validationDeadline = [DateTime]::UtcNow.AddSeconds(30)
  do {
    Start-Sleep -Milliseconds 500
    $events = @(Get-Content $logFile) | Select-Object -Skip $previousLines
  } until (($events -match 'window_placement_preserved') -or [DateTime]::UtcNow -ge $validationDeadline)
  if ($native.HasExited) { throw ('App exited during tray: '+$native.ExitCode) }
  $events=@(Get-Content $logFile) | Select-Object -Skip $previousLines
  foreach ($expected in @('system_accent_ready','tray_ready','smtc_ready','vault_ready','styles_session_preserved','window_hidden_tray','window_restored','window_placement_preserved')) {
    if (-not ($events -match $expected)) { throw ('Missing event: '+$expected) }
  }
  $events
  'Tray hide/restore: OK'
} finally {
  if (-not $native.HasExited) {
    $native.Refresh()
    $native.CloseMainWindow() | Out-Null
    if (-not $native.WaitForExit(15000)) { throw 'Validation process did not close' }
  }
}
if ($native.ExitCode -ne 0) { throw ('Exit code: '+$native.ExitCode) }
'Clean exit: OK'
