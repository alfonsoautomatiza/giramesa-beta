[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [string]$AppRepository,
    [string]$AppRepositorySlug = 'wertyMSD/donde-comer',
    [string]$Branch = 'main',
    [string]$BetaRepositorySlug = 'wertyMSD/giramesa-beta',
    [Parameter(Mandatory = $true)]
    [string]$ReleaseNotesFile,
    [string]$ApiBaseUrl,
    [switch]$SkipAndroid,
    [switch]$SkipWeb,
    [switch]$SkipWindows,
    [switch]$SkipIos,
    [switch]$Wait
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Write-Status {
    param([Parameter(Mandatory = $true)][string]$Message)
    Write-Host "[Giramesa] $Message"
}

function Get-CommandPath {
    param([Parameter(Mandatory = $true)][string]$Name)
    $command = Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $command) {
        throw "No se encontró '$Name' en PATH. Instalalo por separado antes de continuar."
    }
    return $command.Source
}

function Invoke-Native {
    param(
        [Parameter(Mandatory = $true)][string]$Command,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$FailureMessage,
        [switch]$AllowFailure
    )
    $output = @(& $Command @Arguments 2>&1)
    $exitCode = $LASTEXITCODE
    if (-not $AllowFailure -and $exitCode -ne 0) {
        throw "$FailureMessage (código $exitCode)."
    }
    return [pscustomobject]@{
        ExitCode = $exitCode
        Output = @($output | ForEach-Object { "$_" })
        Text = ($output | ForEach-Object { "$_" }) -join "`n"
    }
}

function Invoke-Git {
    param(
        [Parameter(Mandatory = $true)][string]$Git,
        [Parameter(Mandatory = $true)][string]$Repository,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$FailureMessage
    )
    return Invoke-Native -Command $Git -Arguments (@('-C', $Repository) + $Arguments) -FailureMessage $FailureMessage
}

function Invoke-Gh {
    param(
        [Parameter(Mandatory = $true)][string]$Gh,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$FailureMessage,
        [switch]$AllowFailure
    )
    return Invoke-Native -Command $Gh -Arguments $Arguments -FailureMessage $FailureMessage -AllowFailure:$AllowFailure
}

function Assert-RepositorySlug {
    param([Parameter(Mandatory = $true)][string]$Value)
    if ($Value -notmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' -or $Value -match '(^|/)(\.|\.\.)($|/)') {
        throw "Slug de repositorio no válido: $Value"
    }
}

function Get-FlutterReleaseMetadata {
    param([Parameter(Mandatory = $true)][string]$PubspecPath)
    if (-not (Test-Path -LiteralPath $PubspecPath -PathType Leaf)) {
        throw "No existe el archivo Flutter requerido: $PubspecPath"
    }

    $strictUtf8 = New-Object System.Text.UTF8Encoding($false, $true)
    try {
        $content = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $PubspecPath).Path, $strictUtf8)
    } catch {
        throw 'app/pubspec.yaml debe ser texto UTF-8 válido.'
    }

    $versionLines = @($content -split "`r?`n" | Where-Object { $_ -match '^version:' })
    if ($versionLines.Count -ne 1) {
        throw "app/pubspec.yaml debe contener exactamente una clave top-level 'version:'; se encontraron $($versionLines.Count)."
    }

    $semVer = '(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-((?:0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*)(?:\.(?:0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*))*))?'
    $match = [regex]::Match($versionLines[0], "^version:[ `t]*(?<version>$semVer)\+(?<build>[1-9][0-9]*)[ `t]*$")
    if (-not $match.Success) {
        throw "La versión Flutter debe tener el formato SemVer estricto X.Y.Z[-prerelease]+N, con N entero positivo; por ejemplo 'version: 0.1.1+2'."
    }

    $buildNumber = 0
    if (-not [int]::TryParse($match.Groups['build'].Value, [ref]$buildNumber) -or $buildNumber -lt 1) {
        throw 'El build number de app/pubspec.yaml excede el rango de entero positivo admitido por las plataformas.'
    }

    return [pscustomobject]@{
        Version = $match.Groups['version'].Value
        BuildNumber = $buildNumber
    }
}

function Assert-SafeReleaseNotes {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "No existe ReleaseNotesFile: $Path"
    }
    $resolved = (Resolve-Path -LiteralPath $Path).Path
    $bytes = [System.IO.File]::ReadAllBytes($resolved)
    if ($bytes.Length -eq 0 -or $bytes.Length -gt 40960) {
        throw 'Las notas deben contener entre 1 byte y 40 KiB para respetar el límite de workflow_dispatch.'
    }
    $strictUtf8 = New-Object System.Text.UTF8Encoding($false, $true)
    try {
        $content = $strictUtf8.GetString($bytes)
    } catch {
        throw 'Las notas deben ser texto UTF-8 válido.'
    }
    if ([string]::IsNullOrWhiteSpace($content) -or $content.IndexOf([char]0) -ge 0) {
        throw 'Las notas están vacías o contienen bytes nulos.'
    }
    $patterns = @(
        '-----BEGIN [A-Z ]*PRIVATE KEY-----',
        'ghp_[A-Za-z0-9]{30,}',
        'github_pat_[A-Za-z0-9_]{30,}',
        'AKIA[0-9A-Z]{16}',
        '(?i)(?:api[_-]?key|client[_-]?secret|password|access[_-]?token)\s*[:=]\s*["''][^"''\s]{8,}["'']'
    )
    foreach ($pattern in $patterns) {
        if ($content -match $pattern) {
            throw 'Las notas parecen contener una credencial o clave privada; el valor no se mostrará.'
        }
    }
    return $bytes
}

function Test-PublicIpAddress {
    param([Parameter(Mandatory = $true)][System.Net.IPAddress]$Address)
    if ($Address.IsIPv4MappedToIPv6) { $Address = $Address.MapToIPv4() }
    if ($Address.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork) {
        $bytes = $Address.GetAddressBytes()
        if ($bytes[0] -in @(0, 10, 127) -or $bytes[0] -ge 224) { return $false }
        if ($bytes[0] -eq 169 -and $bytes[1] -eq 254) { return $false }
        if ($bytes[0] -eq 172 -and $bytes[1] -ge 16 -and $bytes[1] -le 31) { return $false }
        if ($bytes[0] -eq 192 -and $bytes[1] -eq 168) { return $false }
        if ($bytes[0] -eq 100 -and $bytes[1] -ge 64 -and $bytes[1] -le 127) { return $false }
        return $true
    }
    if ([System.Net.IPAddress]::IsLoopback($Address) -or $Address.IsIPv6LinkLocal -or $Address.IsIPv6SiteLocal) { return $false }
    $bytes = $Address.GetAddressBytes()
    return (($bytes[0] -band 0xFE) -ne 0xFC -and $bytes[0] -ne 0xFF)
}

function Assert-PublicHttpsUrl {
    param([Parameter(Mandatory = $true)][string]$Value)
    $uri = $null
    if (-not [System.Uri]::TryCreate($Value, [System.UriKind]::Absolute, [ref]$uri) -or
        $uri.Scheme -ne 'https' -or -not $uri.Host -or $uri.UserInfo -or $uri.Query -or $uri.Fragment) {
        throw 'ApiBaseUrl debe ser una URL HTTPS pública sin credenciales, query ni fragmento.'
    }
    if ($uri.Host -eq 'localhost' -or $uri.Host.EndsWith('.localhost') -or
        $uri.Host.EndsWith('.local') -or $uri.Host.EndsWith('.internal')) {
        throw 'ApiBaseUrl no puede apuntar a localhost ni a una red privada.'
    }
    try {
        $addresses = @([System.Net.Dns]::GetHostAddresses($uri.DnsSafeHost))
    } catch {
        throw 'No se pudo resolver el host de ApiBaseUrl.'
    }
    if ($addresses.Count -eq 0 -or @($addresses | Where-Object { -not (Test-PublicIpAddress $_) }).Count -gt 0) {
        throw 'ApiBaseUrl resuelve a una dirección no pública y fue bloqueada.'
    }
}

function Get-RepositoryData {
    param([string]$Gh, [string]$Slug)
    $result = Invoke-Gh -Gh $Gh -Arguments @('repo', 'view', $Slug, '--json', 'nameWithOwner,visibility,url') -FailureMessage "No se pudo consultar $Slug"
    return ConvertFrom-Json $result.Text
}

function Assert-GithubObjectAbsent {
    param(
        [Parameter(Mandatory = $true)]$Result,
        [Parameter(Mandatory = $true)][string]$ObjectDescription
    )
    if ($Result.ExitCode -eq 0) {
        throw "$ObjectDescription ya existe. Actualizá version: en DONDE_COMER/app/pubspec.yaml; nunca se reutiliza ni sobrescribe una versión."
    }
    if ($Result.Text -notmatch '(?i)(HTTP\s+404|not found)') {
        throw "No se pudo confirmar que $ObjectDescription no exista; se cancela ante un resultado remoto ambiguo."
    }
}

Assert-RepositorySlug $AppRepositorySlug
Assert-RepositorySlug $BetaRepositorySlug
if ($Branch -notmatch '^[A-Za-z0-9._/-]+$' -or $Branch.Contains('..') -or $Branch.StartsWith('/') -or $Branch.EndsWith('/')) {
    throw 'Branch contiene caracteres o segmentos no válidos.'
}
if ($SkipAndroid -and $SkipWeb -and $SkipWindows -and $SkipIos) {
    throw 'No se puede omitir las cuatro plataformas.'
}
if ($ApiBaseUrl) { Assert-PublicHttpsUrl $ApiBaseUrl }

if ([string]::IsNullOrWhiteSpace($AppRepository)) {
    $AppRepository = Join-Path (Split-Path -Parent $PSScriptRoot) 'DONDE_COMER'
}
if (-not (Test-Path -LiteralPath $AppRepository -PathType Container)) {
    throw "No existe el repositorio privado local: $AppRepository"
}
$AppRepository = (Resolve-Path -LiteralPath $AppRepository).Path
$git = Get-CommandPath 'git'
$gh = Get-CommandPath 'gh'

$rootResult = Invoke-Git -Git $git -Repository $AppRepository -Arguments @('rev-parse', '--show-toplevel') -FailureMessage 'AppRepository no es un worktree Git válido'
$repositoryRoot = (Resolve-Path -LiteralPath $rootResult.Text.Trim()).Path
$pathComparison = if ($env:OS -eq 'Windows_NT') { [System.StringComparison]::OrdinalIgnoreCase } else { [System.StringComparison]::Ordinal }
if (-not $repositoryRoot.TrimEnd('\', '/').Equals($AppRepository.TrimEnd('\', '/'), $pathComparison)) {
    throw "AppRepository debe apuntar a la raíz del worktree privado: $repositoryRoot"
}

$status = Invoke-Git -Git $git -Repository $AppRepository -Arguments @('status', '--porcelain', '--untracked-files=normal') -FailureMessage 'No se pudo comprobar el estado del worktree privado'
if ($status.Output.Count -gt 0) {
    throw 'El worktree privado debe estar completamente limpio, incluidos archivos no rastreados. El script no hará commit, stash, pull ni push.'
}
$currentBranch = (Invoke-Git -Git $git -Repository $AppRepository -Arguments @('symbolic-ref', '--quiet', '--short', 'HEAD') -FailureMessage 'El worktree privado está en detached HEAD').Text.Trim()
if ($currentBranch -cne $Branch) {
    throw "El worktree privado está en la rama '$currentBranch', pero se requiere '$Branch'."
}
$headSha = (Invoke-Git -Git $git -Repository $AppRepository -Arguments @('rev-parse', 'HEAD') -FailureMessage 'No se pudo resolver HEAD').Text.Trim()
$originSha = (Invoke-Git -Git $git -Repository $AppRepository -Arguments @('rev-parse', "refs/remotes/origin/$Branch") -FailureMessage "No existe la referencia local origin/$Branch; actualizala manualmente antes de publicar").Text.Trim()
if ($headSha -cne $originSha) {
    throw "HEAD ($headSha) no coincide con origin/$Branch ($originSha). Sincronizá el worktree manualmente; el script no hará pull, merge ni push."
}

$metadata = Get-FlutterReleaseMetadata (Join-Path $AppRepository 'app/pubspec.yaml')
$releaseVersion = $metadata.Version
$buildNumber = $metadata.BuildNumber
$tag = "v$releaseVersion"
$notesBytes = Assert-SafeReleaseNotes $ReleaseNotesFile
$notesBase64 = [Convert]::ToBase64String($notesBytes)

Invoke-Gh -Gh $gh -Arguments @('auth', 'status', '--hostname', 'github.com') -FailureMessage "GitHub CLI no está autenticado. Ejecutá 'gh auth login' por separado; este script no autentica ni recibe tokens" | Out-Null
$appRepositoryData = Get-RepositoryData -Gh $gh -Slug $AppRepositorySlug
$betaRepositoryData = Get-RepositoryData -Gh $gh -Slug $BetaRepositorySlug
$slugComparison = [System.StringComparison]::OrdinalIgnoreCase
if (-not ([string]$appRepositoryData.nameWithOwner).Equals($AppRepositorySlug, $slugComparison) -or $appRepositoryData.visibility -ne 'PRIVATE') {
    throw "$AppRepositorySlug debe existir y ser PRIVATE. El script no cambiará su visibilidad."
}
if (-not ([string]$betaRepositoryData.nameWithOwner).Equals($BetaRepositorySlug, $slugComparison) -or $betaRepositoryData.visibility -ne 'PUBLIC') {
    throw "$BetaRepositorySlug debe existir y ser PUBLIC. El script no cambiará su visibilidad."
}

$encodedBranch = $Branch.Replace('/', '%2F')
$branchResult = Invoke-Gh -Gh $gh -Arguments @('api', '--method', 'GET', "repos/$AppRepositorySlug/branches/$encodedBranch") -FailureMessage "La rama remota $Branch no existe o no es accesible"
$remoteBranch = ConvertFrom-Json $branchResult.Text
if ([string]$remoteBranch.commit.sha -cne $headSha) {
    throw "El HEAD local no coincide con GitHub $AppRepositorySlug@$Branch. Ejecutá fetch y sincronizá manualmente antes de publicar."
}
Invoke-Gh -Gh $gh -Arguments @('api', '--method', 'GET', "repos/$AppRepositorySlug/contents/.github/workflows/release-test-builds.yml", '-f', "ref=$Branch") -FailureMessage "release-test-builds.yml no existe en $AppRepositorySlug@$Branch" | Out-Null
Invoke-Gh -Gh $gh -Arguments @('workflow', 'view', 'release-test-builds.yml', '--repo', $AppRepositorySlug) -FailureMessage 'El workflow existe como archivo pero GitHub Actions no lo reconoce en la rama predeterminada' | Out-Null

$releaseProbe = Invoke-Gh -Gh $gh -Arguments @('release', 'view', $tag, '--repo', $BetaRepositorySlug, '--json', 'url') -FailureMessage '' -AllowFailure
Assert-GithubObjectAbsent -Result $releaseProbe -ObjectDescription "La Release $tag en $BetaRepositorySlug"
$tagProbe = Invoke-Gh -Gh $gh -Arguments @('api', '--method', 'GET', "repos/$BetaRepositorySlug/git/ref/tags/$tag") -FailureMessage '' -AllowFailure
Assert-GithubObjectAbsent -Result $tagProbe -ObjectDescription "El tag $tag en $BetaRepositorySlug"

$beforeRunsResult = Invoke-Gh -Gh $gh -Arguments @('run', 'list', '--repo', $AppRepositorySlug, '--workflow', 'release-test-builds.yml', '--event', 'workflow_dispatch', '--limit', '100', '--json', 'databaseId') -FailureMessage 'No se pudo obtener la lista inicial de ejecuciones'
$beforeRunIds = @{}
foreach ($run in @(ConvertFrom-Json $beforeRunsResult.Text)) { $beforeRunIds[[string]$run.databaseId] = $true }

$dispatchArguments = @(
    'workflow', 'run', 'release-test-builds.yml',
    '--repo', $AppRepositorySlug,
    '--ref', $Branch,
    '-f', "expected_commit_sha=$headSha",
    '-f', "beta_repository=$BetaRepositorySlug",
    '-f', "release_notes_base64=$notesBase64",
    '-f', "api_base_url=$ApiBaseUrl",
    '-f', "run_android=$((-not $SkipAndroid).ToString().ToLowerInvariant())",
    '-f', "run_web=$((-not $SkipWeb).ToString().ToLowerInvariant())",
    '-f', "run_windows=$((-not $SkipWindows).ToString().ToLowerInvariant())",
    '-f', "run_ios=$((-not $SkipIos).ToString().ToLowerInvariant())"
)

Write-Status "App privada local: $AppRepository"
Write-Status "App remota: $($appRepositoryData.url)@$Branch ($headSha)"
Write-Status "Destino público: $($betaRepositoryData.url)"
Write-Status "Flutter pubspec: versión $releaseVersion, build $buildNumber, tag $tag"
if ($WhatIfPreference) {
    $plannedNotes = "<base64 de notas: $($notesBase64.Length) caracteres>"
    $plannedCommand = "gh workflow run release-test-builds.yml --repo '$AppRepositorySlug' --ref '$Branch' -f expected_commit_sha='$headSha' -f beta_repository='$BetaRepositorySlug' -f release_notes_base64='$plannedNotes' -f api_base_url='$ApiBaseUrl' -f run_android='$((-not $SkipAndroid).ToString().ToLowerInvariant())' -f run_web='$((-not $SkipWeb).ToString().ToLowerInvariant())' -f run_windows='$((-not $SkipWindows).ToString().ToLowerInvariant())' -f run_ios='$((-not $SkipIos).ToString().ToLowerInvariant())'"
    Write-Status "WhatIf comando planificado: $plannedCommand"
}
if (-not $PSCmdlet.ShouldProcess("GitHub Actions en $AppRepositorySlug", "Ejecutar release-test-builds.yml desde $Branch para $tag")) {
    Write-Status 'WhatIf completado: todas las comprobaciones fueron de solo lectura y no se ejecutó workflow_dispatch.'
    return
}

Invoke-Gh -Gh $gh -Arguments $dispatchArguments -FailureMessage 'No se pudo iniciar release-test-builds.yml' | Out-Null
Write-Status 'Workflow solicitado; buscando la ejecución creada.'
$createdRun = $null
for ($attempt = 0; $attempt -lt 12 -and -not $createdRun; $attempt++) {
    Start-Sleep -Seconds 5
    $runsResult = Invoke-Gh -Gh $gh -Arguments @('run', 'list', '--repo', $AppRepositorySlug, '--workflow', 'release-test-builds.yml', '--event', 'workflow_dispatch', '--branch', $Branch, '--limit', '20', '--json', 'databaseId,url,status,conclusion,headSha') -FailureMessage 'No se pudo localizar la ejecución creada'
    foreach ($run in @(ConvertFrom-Json $runsResult.Text)) {
        if (-not $beforeRunIds.ContainsKey([string]$run.databaseId) -and [string]$run.headSha -ceq $headSha) {
            $createdRun = $run
            break
        }
    }
}
if (-not $createdRun) {
    throw "El dispatch fue aceptado, pero no se encontró su run. Revisá https://github.com/$AppRepositorySlug/actions/workflows/release-test-builds.yml"
}

Write-Status "Run: $($createdRun.url)"
Write-Status "Estado: $($createdRun.status)"
if ($Wait) {
    $watch = Invoke-Gh -Gh $gh -Arguments @('run', 'watch', [string]$createdRun.databaseId, '--repo', $AppRepositorySlug, '--exit-status') -FailureMessage 'La ejecución terminó con errores' -AllowFailure
    $finalResult = Invoke-Gh -Gh $gh -Arguments @('run', 'view', [string]$createdRun.databaseId, '--repo', $AppRepositorySlug, '--json', 'url,status,conclusion') -FailureMessage 'No se pudo consultar el estado final'
    $final = ConvertFrom-Json $finalResult.Text
    Write-Status "Estado final: $($final.status) / $($final.conclusion)"
    Write-Status "Run: $($final.url)"
    if ($watch.ExitCode -ne 0) { exit $watch.ExitCode }
}
