param([switch]$Run)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Invoke-Flutter {
    param([string[]]$Arguments)
    & flutter @Arguments
    if ($LASTEXITCODE -ne 0) { throw "flutter $($Arguments -join ' ') falhou ($LASTEXITCODE)." }
}

Push-Location (Split-Path $PSScriptRoot -Parent)
try {
    foreach ($command in @('git', 'flutter')) {
        if (-not (Get-Command $command -ErrorAction SilentlyContinue)) {
            throw "$command não encontrado no PATH. Consulte README.md e abra um novo terminal após instalar."
        }
    }
    Invoke-Flutter -Arguments @('doctor', '-v')
    Invoke-Flutter -Arguments @('config', '--enable-windows-desktop')
    if (-not (Test-Path 'windows')) {
        # Gerar apenas o runner em uma pasta temporária preserva lib, testes e pubspec.
        $staging = Join-Path ([IO.Path]::GetTempPath()) ('music-time-' + [guid]::NewGuid())
        Invoke-Flutter -Arguments @('create', '--platforms=windows', '--project-name', 'music_time', '--no-pub', $staging)
        $windowFile = Join-Path $staging 'windows/runner/main.cpp'
        $resourceFile = Join-Path $staging 'windows/runner/Runner.rc'
        foreach ($file in @($windowFile, $resourceFile)) {
            $content = [IO.File]::ReadAllText($file).Replace('"music_time"', '"Music Time"')
            [IO.File]::WriteAllText($file, $content, [Text.UTF8Encoding]::new($false))
        }
        Copy-Item -LiteralPath (Join-Path $staging 'windows') -Destination 'windows' -Recurse
        Write-Host "Runner gerado. Template temporário: $staging"
    }
    Invoke-Flutter -Arguments @('pub', 'get')
    & dart format lib test
    if ($LASTEXITCODE -ne 0) { throw 'Falha ao formatar o código Dart.' }
    Invoke-Flutter -Arguments @('analyze')
    Invoke-Flutter -Arguments @('test')
    Invoke-Flutter -Arguments @('build', 'windows', '--debug')
    if ($Run) { Invoke-Flutter -Arguments @('run', '-d', 'windows') }
} finally {
    Pop-Location
}
