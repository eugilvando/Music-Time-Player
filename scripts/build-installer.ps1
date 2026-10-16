param([string]$FlutterSdk = $env:FLUTTER_ROOT)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
Push-Location (Split-Path $PSScriptRoot -Parent)
try {
    if (-not $FlutterSdk) {
        $command = Get-Command flutter.bat -ErrorAction Stop
        $FlutterSdk = Split-Path (Split-Path $command.Source -Parent) -Parent
    }
    $flutter = Join-Path $FlutterSdk 'bin/flutter.bat'
    $dart = Join-Path $FlutterSdk 'bin/dart.bat'
    function Invoke-CheckedFlutter {
        param([string[]]$Arguments)
        & $flutter @Arguments
        if ($LASTEXITCODE -ne 0) { throw "Flutter falhou: $($Arguments -join ' ')" }
    }
    Invoke-CheckedFlutter @('pub', 'get')
    & $dart format --output=none --set-exit-if-changed test/support tool
    if ($LASTEXITCODE -ne 0) { throw 'Formatação pendente nas ferramentas públicas.' }
    & $dart analyze --fatal-infos
    if ($LASTEXITCODE -ne 0) { throw 'Análise estática falhou.' }
    Invoke-CheckedFlutter @('build', 'windows', '--release')
    $bundle = Join-Path $PWD 'build/windows/x64/runner/Release'
    # Deploy portable native-asset references instead of build-machine paths.
    $nativeManifest = Join-Path $bundle 'data/flutter_assets/NativeAssetsManifest.json'
    Copy-Item -LiteralPath $nativeManifest -Destination (Join-Path $bundle 'native_assets.json') -Force
    $previousLibmpv = [Environment]::GetEnvironmentVariable('MUSIC_TIME_LIBMPV', 'Process')
    try {
        $env:MUSIC_TIME_LIBMPV = Join-Path $bundle 'libmpv-2.dll'
        Invoke-CheckedFlutter @('test', '--concurrency=1')
    } finally {
        [Environment]::SetEnvironmentVariable('MUSIC_TIME_LIBMPV', $previousLibmpv, 'Process')
    }
    & (Join-Path $PSScriptRoot 'test-windows-integration.ps1') -Executable (Join-Path $bundle 'music_time.exe')
    if ($LASTEXITCODE -ne 0) { throw 'Falha na integração nativa.' }
    & (Join-Path $PSScriptRoot 'test-data-restart.ps1') -Executable (Join-Path $bundle 'music_time.exe')
    if ($LASTEXITCODE -ne 0) { throw 'Falha na validação de dados.' }
    if (-not (Test-Path -LiteralPath 'LICENSES/FLUTTER-NOTICES.txt') -or -not (Test-Path -LiteralPath 'THIRD_PARTY_NOTICES.md')) {
        throw 'Avisos das dependências ausentes.'
    }
    $vswhere = 'C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe'
    $visualStudio = & $vswhere -latest -products '*' -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if (-not $visualStudio) { throw 'Toolchain C++ não encontrada.' }
    $redistRoot = Join-Path $visualStudio 'VC/Redist/MSVC'
    $version = Get-ChildItem -LiteralPath $redistRoot -Directory | Where-Object { $_.Name -match '^\d+\.\d+\.\d+$' } | Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1
    if (-not $version) { throw 'Runtime redistribuível não encontrado.' }
    $runtime = Join-Path $version.FullName 'x64/Microsoft.VC143.CRT'
    Get-ChildItem -LiteralPath $runtime -Filter '*.dll' | Copy-Item -Destination $bundle
    $compilerPaths = @(
        (Join-Path $env:LOCALAPPDATA 'Programs/Inno Setup 6/ISCC.exe'),
        'C:\Program Files (x86)\Inno Setup 6\ISCC.exe',
        'C:\Program Files\Inno Setup 6\ISCC.exe'
    )
    $compiler = $compilerPaths | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if (-not $compiler) { throw 'Instale Inno Setup 6 para empacotar.' }
    & $compiler installer/music_time.iss
    if ($LASTEXITCODE -ne 0) { throw 'Falha ao criar instalador.' }
} finally {
    Pop-Location
}
