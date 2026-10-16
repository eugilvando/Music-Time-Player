param([Parameter(Mandatory=$true)][string]$Executable)
$ErrorActionPreference='Stop'
$root = [IO.Path]::GetFullPath((Join-Path $env:TEMP 'music_time_validation_profile'))
if ((Split-Path $root -Leaf) -ne 'music_time_validation_profile') { throw 'Invalid validation directory' }
New-Item -ItemType Directory -Force -Path $root | Out-Null
$dbPath = Join-Path $root 'music_time.db'
$request = Join-Path $root 'maintenance-request.json'
$receipt = Join-Path $root 'maintenance-validation-result.txt'
$original = Join-Path $root 'original-fixture.wav'
[IO.File]::WriteAllBytes($original, [byte[]](1,2,3))
$dll = Join-Path (Split-Path $Executable) 'sqlite3.dll'
Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class DataRestartProbe {
 [DllImport(@"$dll", CallingConvention=CallingConvention.Cdecl)] static extern int sqlite3_open_v2([MarshalAs(UnmanagedType.LPUTF8Str)] string path, out IntPtr db, int flags, IntPtr vfs);
 [DllImport(@"$dll", CallingConvention=CallingConvention.Cdecl)] static extern int sqlite3_prepare_v2(IntPtr db, [MarshalAs(UnmanagedType.LPUTF8Str)] string sql, int n, out IntPtr stmt, IntPtr tail);
 [DllImport(@"$dll", CallingConvention=CallingConvention.Cdecl)] static extern int sqlite3_step(IntPtr stmt);
 [DllImport(@"$dll", CallingConvention=CallingConvention.Cdecl)] static extern long sqlite3_column_int64(IntPtr stmt, int column);
 [DllImport(@"$dll", CallingConvention=CallingConvention.Cdecl)] static extern int sqlite3_finalize(IntPtr stmt);
 [DllImport(@"$dll", CallingConvention=CallingConvention.Cdecl)] static extern int sqlite3_close(IntPtr db);
 [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindow(string cls, string title);
 [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr hwnd, uint message, IntPtr w, IntPtr l);
 public static long Count(string path, string table) {
   if (table != "tracks" && table != "playlists" && table != "local_sources" && table != "catalog_search") throw new Exception("Invalid table");
   IntPtr db, stmt = IntPtr.Zero;
   if (sqlite3_open_v2(path, out db, 1, IntPtr.Zero) != 0) throw new Exception("Read-only database open failed");
   try {
     if (sqlite3_prepare_v2(db, "SELECT COUNT(*) FROM " + table, -1, out stmt, IntPtr.Zero) != 0 || sqlite3_step(stmt) != 100) throw new Exception("Count failed");
     return sqlite3_column_int64(stmt, 0);
   } finally { if (stmt != IntPtr.Zero) sqlite3_finalize(stmt); sqlite3_close(db); }
 }
}
"@
function Wait-Request($process) {
  $deadline = [DateTime]::UtcNow.AddSeconds(20)
  while (Test-Path -LiteralPath $request) {
    if ($process.HasExited) { throw 'Maintenance process exited before applying request' }
    if ([DateTime]::UtcNow -gt $deadline) { throw 'Maintenance timeout' }
    Start-Sleep -Milliseconds 200
  }
  Start-Sleep -Seconds 3
  if (-not (Test-Path -LiteralPath $receipt) -or [IO.File]::ReadAllText($receipt).Trim() -ne 'ok') { throw 'Maintenance did not complete all steps' }
}
function Close-Validation($process) {
  if (-not $process -or $process.HasExited) { return }
  $window = [DataRestartProbe]::FindWindow('FLUTTER_RUNNER_WIN32_WINDOW', 'Music Time (Validacao)')
  if ($window -eq [IntPtr]::Zero) { throw 'Validation window missing' }
  [DataRestartProbe]::PostMessage($window, 0x10, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
  if (-not $process.WaitForExit(15000)) { throw 'Validation exit timeout' }
  if ($process.ExitCode -ne 0) { throw 'Validation exit failed' }
}
$tables = @{}
foreach ($table in @('tracks','local_sources','local_source_tracks','playlists','playlist_entries','favorites','history','playback','queue')) { $tables[$table] = @() }
$tables.tracks = @(@{ id='native-fixture'; title='DEMO original'; artist='Fixture'; album=''; path=$original; metadata='{}'; cover=$null; added_at=$null })
$tables.local_sources = @(@{ id='fixture'; label='DEMO'; active=1 })
$tables.local_source_tracks = @(@{ source_id='fixture'; track_id='native-fixture' })
$tables.playlists = @(@{ id=1; name='DEMO backup' })
$tables.playlist_entries = @(@{ id=1; playlist_id=1; track_id='native-fixture'; ordinal=0 })
$backup = @{ format='music_time_backup'; version=1; schema=6; tables=$tables; preferences=@{ theme='dark' } } | ConvertTo-Json -Depth 10 -Compress
[IO.File]::Delete($receipt)
[IO.File]::WriteAllText($request, (@{version=1;action='restore';backup=$backup} | ConvertTo-Json -Depth 12 -Compress))
$first=$null; $second=$null
try {
  $first = Start-Process -FilePath $Executable -ArgumentList @('--validation-profile') -WindowStyle Hidden -PassThru
  Wait-Request $first
  foreach ($table in @('tracks','playlists','local_sources','catalog_search')) { if ([DataRestartProbe]::Count($dbPath, $table) -ne 1) { throw "Native restore failed: $table" } }
  'Native backup restore: OK'
  [IO.File]::Delete($receipt)
  [IO.File]::WriteAllText($request, '{"version":1,"action":"reset"}')
  $second = Start-Process -FilePath $Executable -ArgumentList @('--validation-profile', ('--restart-after='+$first.Id)) -WindowStyle Hidden -PassThru
  Start-Sleep -Milliseconds 600
  if ($second.HasExited -or -not (Test-Path $request) -or [DataRestartProbe]::Count($dbPath,'tracks') -ne 1) { throw 'Restart did not wait for previous process' }
  'Restart waits for previous process: OK'
  Close-Validation $first
  Wait-Request $second
  foreach ($table in @('tracks','playlists','local_sources','catalog_search')) { if ([DataRestartProbe]::Count($dbPath, $table) -ne 0) { throw "Native reset failed: $table" } }
  if (-not (Test-Path -LiteralPath $original)) { throw 'Original fixture was deleted' }
  'Native reset preserves original fixture: OK'
  Close-Validation $second
  'Maintenance restart clean exit: OK'
} finally {
  Close-Validation $first
  Close-Validation $second
}
