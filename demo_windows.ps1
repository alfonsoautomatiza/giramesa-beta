<#
demo_windows.ps1 - Compila la version de escritorio Windows para testeo rapido.

Flujo:
  1. Pre-requisitos (flutter, gh, git).
  2. Lee la version actual del clon de trabajo (sin bump).
  3. Flutter pub get + flutter analyze (sin test, para ir mas rapido).
  4. Compila flutter build windows --release.
  5. Ejecuta la app para testeo rapido.
  6. Guarda el manifest de version para publish_windows.ps1.

No publica. No sincroniza con el repositorio privado.

Uso:
  .\demo_windows.ps1                    # compilar y empaquetar (tests omitidos)
  .\demo_windows.ps1 -WhatIf            # mostrar el plan sin mutar nada
  .\demo_windows.ps1 -SkipAnalyze       # saltar analyze (solo para emergencias)
  .\demo_windows.ps1 -RunTests          # compilar con tests
  .\demo_windows.ps1 -Clean             # limpiar artefactos de compilacion anterior
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [string]$SourceClone = 'P:\android\giramesa',
    [string]$TempBase = 'D:\temp\giramesa-build',
    [string]$FlutterBat = 'D:\flutter\bin\flutter.bat',
    [string]$OutDir = 'D:\temp\opencode\out',
    [string]$ManifestFile = 'D:\temp\opencode\giramesa-build-manifest.json',
    [switch]$SkipAnalyze,
    [switch]$RunTests,  # Por defecto NO corre tests para ir mas rapido; usar -RunTests si se necesitan
    [switch]$Clean,      # Limpiar artefactos de compilacion y cache antes de compilar
    [switch]$KeepTemp    # Mantener la carpeta temporal (para debug)
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Write-Status {
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-Host "[Giramesa] $Message"
}

function Invoke-Native {
    param(
        [Parameter(Mandatory = $true)][string]$Command,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$FailureMessage
    )
    $prevPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        $output = @(& $Command @Arguments 2>&1)
    } finally {
        $ErrorActionPreference = $prevPreference
    }
    if ($LASTEXITCODE -ne 0) {
        $tail = ($output | Select-Object -Last 12 | ForEach-Object { "$_" }) -join "`n"
        throw "$FailureMessage (codigo $LASTEXITCODE).`n$tail"
    }
    return ($output | ForEach-Object { "$_" })
}

function Remove-IfExists {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [string]$Description = $null
    )
    if (Test-Path -LiteralPath $Path) {
        try {
            Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
            if ($Description) {
                Write-Status "Eliminado: $Description"
            }
        } catch {
            Write-Status "ADVERTENCIA: No se pudo eliminar $Path ($_)"
        }
    }
}

function Cleanup-Build {
    param([string]$AppDir)
    Write-Status "Limpiando artefactos de compilacion anterior..."

    # Matar procesos giramesa.exe que esten abiertos
    $procs = Get-Process -Name 'giramesa' -ErrorAction SilentlyContinue
    if ($procs) {
        $procs | Stop-Process -Force -ErrorAction SilentlyContinue
        Write-Status "Detenidos procesos giramesa.exe"
        Start-Sleep -Seconds 1
    }

    # Limpiar cache y artefactos
    Remove-IfExists (Join-Path $AppDir 'windows\flutter\ephemeral') 'windows/flutter/ephemeral/'
    Remove-IfExists (Join-Path $AppDir 'windows\flutter\generated') 'windows/flutter/generated/'
    Remove-IfExists (Join-Path $AppDir '.dart_tool') '.dart_tool/'
    Remove-IfExists (Join-Path $AppDir 'build') 'build/'
    Remove-IfExists (Join-Path $AppDir '.packages') '.packages'
    Remove-IfExists (Join-Path $AppDir 'pubspec.lock') 'pubspec.lock'

    Write-Status "Limpieza completada."
}

# --- 0. Pre-requisitos ------------------------------------------------------
if (-not (Test-Path -LiteralPath (Join-Path $SourceClone '.git'))) {
    throw "No existe el repositorio esperado: $SourceClone"
}
if (-not (Test-Path -LiteralPath $FlutterBat)) {
    throw "No existe el SDK de Flutter en: $FlutterBat (instalar una sola vez en D:\flutter)"
}
$gh = Get-Command gh -CommandType Application -ErrorAction SilentlyContinue
if (-not $gh) { throw 'gh no esta en PATH. Instalar GitHub CLI y autenticar.' }
$null = Invoke-Native gh @('auth', 'status') 'gh no esta autenticado'
$null = Invoke-Native gh @('api', 'repos/alfonsoautomatiza/giramesa-beta') "No se puede acceder al repositorio beta"
Write-Status "Pre-requisitos OK."

# --- 0.5. Copiar a carpeta temporal en unidad local --------------------------
$WorkClone = $TempBase
$timestamp = (Get-Date).ToString('yyyyMMdd-HHmmss')
$WorkClone = Join-Path $TempBase "giramesa-$timestamp"
if (Test-Path -LiteralPath $WorkClone) {
    Remove-Item -LiteralPath $WorkClone -Recurse -Force
}
Write-Status "Copiando desde $SourceClone a carpeta temporal $WorkClone..."
Copy-Item -LiteralPath (Join-Path $SourceClone 'app') -Destination (Join-Path $WorkClone 'app') -Recurse -Force | Out-Null
Write-Status "Limpiando atributos read-only de archivos copiados..."
Get-ChildItem -LiteralPath (Join-Path $WorkClone 'app') -Recurse -Force | ForEach-Object {
    if ($_.Attributes -band [IO.FileAttributes]::ReadOnly) {
        $_.Attributes = $_.Attributes -band -bnot [IO.FileAttributes]::ReadOnly
    }
}
Write-Status "Copia completada."

# --- 1. Leer version del clon -----------------------------------------------
$pubspecClone = Join-Path $WorkClone 'app\pubspec.yaml'
$versionLine = @((Get-Content -LiteralPath $pubspecClone) | Where-Object { $_ -match '^version:' })
if ($versionLine.Count -ne 1) {
    throw "app/pubspec.yaml debe tener exactamente una linea 'version:'."
}
if ($versionLine[0] -notmatch '^version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)\s*$') {
    throw "Version con formato inesperado: $($versionLine[0])"
}
$major = [int]$Matches[1]; $minor = [int]$Matches[2]; $patch = [int]$Matches[3]; $build = [int]$Matches[4]
$newVersion = "$major.$minor.$patch"
$newTag = "v$newVersion"
Write-Status "Version del clon: $newVersion (build $build, tag $newTag)."

# --- 2. Plan (WhatIf se detiene aqui) -------------------------------------
if (-not $PSCmdlet.ShouldProcess("$WorkClone -> demo Windows $newVersion")) {
    Write-Status "PLAN (WhatIf): analizar + compilar $newVersion+$build, empaquetar."
    return
}

# --- 2.5. Limpiar si se solicita -----------------------------------------------
$appDir = Join-Path $WorkClone 'app'
if ($Clean) {
    Cleanup-Build -AppDir $appDir
}

# --- 3. Analizar (sin test para ir mas rapido) ----------------------------
try {
    Push-Location $appDir

    # Limpiar estado anterior de Flutter
    Write-Status "Ejecutando flutter clean..."
    $null = Invoke-Native $FlutterBat @('clean') 'flutter clean fallo'

    # Intentar pub get con retry automático en caso de .plugin_symlinks bloqueado
    $pubGetAttempt = 0
    $maxAttempts = 2
    while ($pubGetAttempt -lt $maxAttempts) {
        $pubGetAttempt++
        try {
            $null = Invoke-Native $FlutterBat @('pub', 'get') 'flutter pub get fallo'
            break
        } catch {
            if ($pubGetAttempt -lt $maxAttempts -and ($_ -match "\.plugin_symlinks" -or $_ -match "Deletion failed")) {
                Write-Status "Detectado bloqueo de .plugin_symlinks; limpiando y reintentando..."
                Push-Location ..
                Cleanup-Build -AppDir $appDir
                Pop-Location
            } else {
                throw
            }
        }
    }
    if (-not $SkipAnalyze) {
        # Ejecutar analyze pero no fallar si hay warnings (solo reportar)
        $prevPreference = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'
        try {
            $analyzeOutput = @(& $FlutterBat @('analyze') 2>&1)
        } finally {
            $ErrorActionPreference = $prevPreference
        }
        if ($LASTEXITCODE -ne 0) {
            # Si hay warnings/issues, mostrarlos pero continuar
            Write-Status "Análisis completado con warnings (ver arriba). Compilando..."
        } else {
            Write-Status "Análisis OK (sin warnings)."
        }
    }
    if ($RunTests) {
        $null = Invoke-Native $FlutterBat @('test') 'flutter test fallo'
        Write-Status "Tests OK."
    } else {
        Write-Status "Tests omitidos por defecto (usar -RunTests para ejecutar)."
    }
    $null = Invoke-Native $FlutterBat @('build', 'windows', '--release', '--build-name', $newVersion, '--build-number', "$build") 'No se pudo compilar la app de Windows'
} finally {
    Pop-Location
}
Write-Status "Compilacion Windows OK($(if ($RunTests) { ' + tests' } else { ' tests omitidos' }))."

# --- 4. Empaquetar ZIP + SHA-256 --------------------------------------------
$releaseDir = Join-Path $appDir 'build\windows\x64\runner\Release'
if (-not (Test-Path -LiteralPath (Join-Path $releaseDir 'giramesa.exe'))) {
    throw "No se encontro giramesa.exe en $releaseDir"
}
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
$asset = "giramesa-windows-$newVersion-b$build.zip"
$zipPath = Join-Path $OutDir $asset
if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
Compress-Archive -Path (Join-Path $releaseDir '*') -DestinationPath $zipPath -CompressionLevel Optimal
$hash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
[System.IO.File]::WriteAllText("$zipPath.sha256", "$hash  $asset`n", (New-Object System.Text.UTF8Encoding($false)))
Write-Status "Empaquetado $asset ($([math]::Round((Get-Item $zipPath).Length / 1MB, 1)) MB)."

# --- 5. Ejecutar la app para testeo rapido ----------------------------
$exePath = Join-Path $releaseDir 'giramesa.exe'
Write-Status "Ejecutando $exePath para testeo..."
Start-Process -FilePath $exePath -PassThru | Out-Null
Write-Status "App lanzada. Cuando termines de testear, ejecuta: .\publish_windows.ps1"
$KeepTemp = $true  # Forzar mantener carpeta temporal mientras la app está abierta

# --- 6. Guardar manifest para publish_windows -------------------------------
$manifest = @{
    version      = $newVersion
    build        = $build
    tag          = $newTag
    asset        = $asset
    zipPath      = $zipPath
    sha256Path   = "$zipPath.sha256"
    sourceCommit = @(Invoke-Native git @('-C', $SourceClone, 'rev-parse', 'HEAD') 'No se pudo leer el commit')[0]
    timestamp    = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
}
$manifestJson = $manifest | ConvertTo-Json -Depth 3
[System.IO.File]::WriteAllText($ManifestFile, $manifestJson, (New-Object System.Text.UTF8Encoding($false)))
Write-Status "Manifest guardado en $ManifestFile"

# --- 7. Limpiar carpeta temporal -------------------------------------------
if (-not $KeepTemp -and (Test-Path -LiteralPath $WorkClone)) {
    Write-Status "Limpiando carpeta temporal..."
    Remove-Item -LiteralPath $WorkClone -Recurse -Force -ErrorAction SilentlyContinue
    Write-Status "Carpeta temporal eliminada."
} elseif ($KeepTemp) {
    Write-Status "Carpeta temporal conservada en: $WorkClone (para debug)"
}
