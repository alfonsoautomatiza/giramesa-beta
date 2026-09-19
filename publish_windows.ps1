<#
publish_windows.ps1 - Publica la version de escritorio Windows como GitHub Release.

Requiere que demo_windows.ps1 se haya ejecutado antes (crea el manifest).
Flujo:
  1. Lee el manifest generado por demo_windows.ps1.
  2. Publica la Release en el repositorio beta via gh.
  3. Devuelve el commit de version al repositorio privado en P:.

Uso:
  .\publish_windows.ps1                    # publicar el ultimo build de demo_windows
  .\publish_windows.ps1 -WhatIf            # mostrar el plan sin mutar nada
  .\publish_windows.ps1 -ManifestFile .\manifiesto.json   # usar un manifest especifico
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [string]$BetaRepositorySlug = 'alfonsoautomatiza/giramesa-beta',
    [string]$PrivateRepo = 'P:\android\giramesa',
    [string]$WorkClone = 'D:\temp\opencode\giramesa-work',
    [string]$ManifestFile = 'D:\temp\opencode\giramesa-build-manifest.json',
    [string]$Branch = 'master'
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

# --- 0. Pre-requisitos ------------------------------------------------------
if (-not (Test-Path -LiteralPath (Join-Path $PrivateRepo '.git'))) {
    throw "No existe el repositorio esperado: $PrivateRepo"
}

$manifest = $null
$newVersion = '???'
$newTag = '??? '
$zipPath = ''
$sha256Path = ''
$sourceCommit = ''

if (Test-Path -LiteralPath $ManifestFile) {
    $manifest = Get-Content -LiteralPath $ManifestFile -Raw | ConvertFrom-Json
    $newVersion = $manifest.version
    $newTag = $manifest.tag
    $zipPath = $manifest.zipPath
    $sha256Path = $manifest.sha256Path
    $sourceCommit = $manifest.sourceCommit
}

$gh = Get-Command gh -CommandType Application -ErrorAction SilentlyContinue
if (-not $gh) { throw 'gh no esta en PATH. Instalar GitHub CLI y autenticar.' }
$null = Invoke-Native gh @('auth', 'status') 'gh no esta autenticado'
$null = Invoke-Native gh @('api', "repos/$BetaRepositorySlug") "No se puede acceder al repositorio beta $BetaRepositorySlug"
Write-Status "Pre-requisitos OK."

# --- 1. Plan (WhatIf se detiene aqui) -------------------------------------
$planMsg = if ($manifest) { "publicar $newVersion desde $zipPath en $BetaRepositorySlug" } else { "publicar release (ejecuta demo_windows.ps1 primero para generar el manifest)" }
if (-not $PSCmdlet.ShouldProcess("$PrivateRepo -> Release $newTag en $BetaRepositorySlug")) {
    Write-Status "PLAN (WhatIf): $planMsg"
    return
}

if (-not $manifest) {
    throw "No existe el manifest de build: $ManifestFile. Ejecuta demo_windows.ps1 primero."
}

# --- 2. Verificar artifacts existen ---------------------------------------
if (-not (Test-Path -LiteralPath $zipPath)) {
    throw "No se encontro el ZIP en $zipPath. Ejecuta demo_windows.ps1 primero."
}
if (-not (Test-Path -LiteralPath $sha256Path)) {
    throw "No se encontro el SHA-256 en $sha256Path."
}

# --- 3. Notas de release (generar si no existen) ---------------------
$releaseNotesPath = Join-Path (Split-Path $ManifestFile) "release-notes-$newVersion.md"
if (-not (Test-Path -LiteralPath $releaseNotesPath)) {
    $notes = @(
        '## Que probar',
        '- Version de escritorio Windows para pruebas.',
        '',
        '## Cambios visibles',
        "- Reconstruccion automatica de la app de escritorio para Windows ($newVersion).",
        '',
        '## Problemas conocidos',
        '- Requiere Windows 10/11 de 64 bits. Descomprimir el ZIP y ejecutar giramesa.exe.',
        '- El mapa de Google no esta disponible en Windows: la ubicacion se ingresa por coordenadas.',
        '- "Entrar con Google" no esta disponible en Windows: usar email y contrasena.',
        '',
        "Build number: $($manifest.build)",
        "Source commit: $sourceCommit"
    )
    [System.IO.File]::WriteAllLines($releaseNotesPath, ($notes -join "`n"), (New-Object System.Text.UTF8Encoding($false)))
    Write-Status "Notas de release generadas en $releaseNotesPath"
}

# --- 4. Publicar la Release ------------------------------------------------
$created = Invoke-Native gh @('release', 'create', $newTag, $zipPath, "$zipPath.sha256", '--repo', $BetaRepositorySlug, '--title', "Giramesa $newVersion", '--notes-file', $releaseNotesPath) 'No se pudo publicar la Release'
Write-Status "Release publicada: $(@($created | Where-Object { $_ -match '^https://' } | Select-Object -First 1))"

# --- 5. Devolver el commit al repositorio privado ---------------------------
Invoke-Native git @('-C', $PrivateRepo, 'fetch', $WorkClone, $Branch) 'No se pudo devolver el commit al repositorio privado'
Invoke-Native git @('-C', $PrivateRepo, 'merge', '--ff-only', 'FETCH_HEAD') 'El repositorio privado divergio del clon'
Write-Status "El repositorio privado quedo en $newVersion+$($manifest.build) (sin push a origin; requiere credenciales)."
Write-Status "Hecho. Source commit: $sourceCommit"
