[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [string]$AppRepository = (Join-Path (Split-Path -Parent $PSScriptRoot) 'DONDE_COMER'),
    [string]$Owner = 'wertyMSD',
    [string]$Repository = 'giramesa-beta',
    [string]$ReleaseNotesFile,
    [string]$ApiBaseUrl,
    [switch]$SkipTests,
    [switch]$Prerelease,
    [switch]$KeepArtifacts,
    [string]$ApkSignerPath
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

function Write-Status {
    param([string]$Message)
    Write-Host "[Giramesa] $Message"
}

function Invoke-Native {
    param(
        [Parameter(Mandatory = $true)][string]$Command,
        [string[]]$Arguments = @(),
        [string]$FailureMessage = 'El comando externo ha fallado.',
        [switch]$AllowFailure,
        [switch]$ShowOutput,
        [string]$DisplayCommand
    )

    if ($DisplayCommand) {
        Write-Status "Comando: $DisplayCommand"
    }

    $output = @(& $Command @Arguments 2>&1)
    $exitCode = $LASTEXITCODE
    if ($ShowOutput -and $output.Count -gt 0) {
        $output | ForEach-Object { Write-Host $_ }
    }
    if (-not $AllowFailure -and $exitCode -ne 0) {
        throw "$FailureMessage (código $exitCode)."
    }

    return [pscustomobject]@{
        ExitCode = $exitCode
        Output = @($output | ForEach-Object { "$_" })
    }
}

function Get-CommandPath {
    param([Parameter(Mandatory = $true)][string]$Name)

    $command = Get-Command $Name -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $command) {
        throw "No se encontró '$Name' en PATH. Instalalo y abrí una nueva consola antes de continuar."
    }
    return $command.Source
}

function Get-CanonicalPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        throw "No existe el directorio requerido: $Path"
    }
    return (Resolve-Path -LiteralPath $Path).Path.TrimEnd('\', '/')
}

function Assert-SemVer {
    param([Parameter(Mandatory = $true)][string]$Value)

    $semVerPattern = '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-((?:0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*)(?:\.(?:0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*))*))?$'
    if ($Value -notmatch $semVerPattern) {
        throw "La versión debe ser SemVer sin prefijo 'v' ni metadatos, por ejemplo 0.1.0 o 0.2.0-rc.1."
    }
}

function Get-FlutterReleaseMetadata {
    param([Parameter(Mandatory = $true)][string]$PubspecPath)

    $strictUtf8 = New-Object System.Text.UTF8Encoding($false, $true)
    try {
        $content = [System.IO.File]::ReadAllText($PubspecPath, $strictUtf8)
    } catch {
        throw 'app/pubspec.yaml debe ser texto UTF-8 válido.'
    }
    $versionLines = @($content -split "`r?`n" | Where-Object { $_ -match '^version:' })
    if ($versionLines.Count -ne 1) {
        throw "app/pubspec.yaml debe contener exactamente una clave top-level 'version:'; se encontraron $($versionLines.Count)."
    }
    $semVer = '(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-((?:0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*)(?:\.(?:0|[1-9][0-9]*|[0-9]*[A-Za-z-][0-9A-Za-z-]*))*))?'
    $match = [regex]::Match($versionLines[0], "^version:[ `t]*(?<version>$semVer)\+(?<build>[1-9][0-9]*)[ `t]*$")
    $buildNumber = 0
    if (-not $match.Success -or -not [int]::TryParse($match.Groups['build'].Value, [ref]$buildNumber) -or $buildNumber -lt 1) {
        throw "La versión Flutter debe ser X.Y.Z[-prerelease]+N con N entero positivo; por ejemplo 'version: 0.1.1+2'."
    }
    return [pscustomobject]@{ Version = $match.Groups['version'].Value; BuildNumber = $buildNumber }
}

function Test-PublicIpAddress {
    param([Parameter(Mandatory = $true)][System.Net.IPAddress]$Address)

    if ($Address.IsIPv4MappedToIPv6) {
        $Address = $Address.MapToIPv4()
    }
    if ($Address.AddressFamily -eq [System.Net.Sockets.AddressFamily]::InterNetwork) {
        $bytes = $Address.GetAddressBytes()
        if ($bytes[0] -in @(0, 10, 127)) { return $false }
        if ($bytes[0] -eq 169 -and $bytes[1] -eq 254) { return $false }
        if ($bytes[0] -eq 172 -and $bytes[1] -ge 16 -and $bytes[1] -le 31) { return $false }
        if ($bytes[0] -eq 192 -and $bytes[1] -eq 0 -and $bytes[2] -in @(0, 2)) { return $false }
        if ($bytes[0] -eq 192 -and $bytes[1] -eq 168) { return $false }
        if ($bytes[0] -eq 100 -and $bytes[1] -ge 64 -and $bytes[1] -le 127) { return $false }
        if ($bytes[0] -eq 198 -and $bytes[1] -in @(18, 19)) { return $false }
        if ($bytes[0] -eq 198 -and $bytes[1] -eq 51 -and $bytes[2] -eq 100) { return $false }
        if ($bytes[0] -eq 203 -and $bytes[1] -eq 0 -and $bytes[2] -eq 113) { return $false }
        if ($bytes[0] -ge 224) { return $false }
        return $true
    }

    if ([System.Net.IPAddress]::IsLoopback($Address) -or $Address.IsIPv6LinkLocal -or $Address.IsIPv6SiteLocal) {
        return $false
    }
    $bytes = $Address.GetAddressBytes()
    if (($bytes[0] -band 0xFE) -eq 0xFC -or $bytes[0] -eq 0xFF) { return $false }
    if ($bytes[0] -eq 0x20 -and $bytes[1] -eq 0x01 -and $bytes[2] -eq 0x0D -and $bytes[3] -eq 0xB8) { return $false }
    return $true
}

function Assert-PublicHttpsUrl {
    param([Parameter(Mandatory = $true)][string]$Value)

    $uri = $null
    if (-not [System.Uri]::TryCreate($Value, [System.UriKind]::Absolute, [ref]$uri) -or
        $uri.Scheme -ne 'https' -or -not $uri.Host -or $uri.UserInfo -or
        $uri.Query -or $uri.Fragment) {
        throw 'ApiBaseUrl debe ser una URL HTTPS pública, sin credenciales, query ni fragmento.'
    }
    if ($uri.Host -eq 'localhost' -or $uri.Host.EndsWith('.localhost') -or
        $uri.Host.EndsWith('.local') -or $uri.Host.EndsWith('.internal') -or
        ($uri.Host -notmatch '\.' -and $uri.Host -notmatch ':')) {
        throw 'ApiBaseUrl no puede apuntar a localhost, nombres internos ni redes privadas.'
    }

    try {
        $addresses = @([System.Net.Dns]::GetHostAddresses($uri.DnsSafeHost))
    } catch {
        throw 'No se pudo resolver el host público de ApiBaseUrl. Revisá DNS y conectividad.'
    }
    if ($addresses.Count -eq 0 -or @($addresses | Where-Object { -not (Test-PublicIpAddress $_) }).Count -gt 0) {
        throw 'ApiBaseUrl resuelve a una dirección no pública y fue bloqueada.'
    }
}

function Find-ApkSigner {
    param([string]$ExplicitPath)

    if ($ExplicitPath) {
        if (-not (Test-Path -LiteralPath $ExplicitPath -PathType Leaf)) {
            throw "No existe apksigner en la ruta indicada: $ExplicitPath"
        }
        return (Resolve-Path -LiteralPath $ExplicitPath).Path
    }

    $pathCommand = Get-Command 'apksigner.bat' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($pathCommand) {
        return $pathCommand.Source
    }

    $sdkRoots = @(
        $env:ANDROID_SDK_ROOT,
        $env:ANDROID_HOME,
        $(if ($env:LOCALAPPDATA) { Join-Path $env:LOCALAPPDATA 'Android\Sdk' }),
        $(if ($env:USERPROFILE) { Join-Path $env:USERPROFILE 'AppData\Local\Android\Sdk' })
    ) | Where-Object { $_ } | Select-Object -Unique

    $candidates = @()
    foreach ($sdkRoot in $sdkRoots) {
        $buildTools = Join-Path $sdkRoot 'build-tools'
        if (-not (Test-Path -LiteralPath $buildTools -PathType Container)) { continue }
        foreach ($directory in Get-ChildItem -LiteralPath $buildTools -Directory -ErrorAction SilentlyContinue) {
            $parsedVersion = $null
            if (-not [version]::TryParse($directory.Name, [ref]$parsedVersion)) { continue }
            $candidate = Join-Path $directory.FullName 'apksigner.bat'
            if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                $candidates += [pscustomobject]@{ Version = $parsedVersion; Path = $candidate }
            }
        }
    }
    $latest = $candidates | Sort-Object Version -Descending | Select-Object -First 1
    if (-not $latest) {
        throw "No se encontró apksigner.bat. Instalá Android SDK Build-Tools o usá -ApkSignerPath 'C:\ruta\apksigner.bat'."
    }
    return $latest.Path
}

function Get-PythonCommand {
    foreach ($candidate in @('python', 'python3', 'py')) {
        $command = Get-Command $candidate -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $command) { continue }
        $prefix = @()
        if ($candidate -eq 'py') { $prefix = @('-3') }
        $probe = Invoke-Native -Command $command.Source -Arguments ($prefix + @('--version')) -AllowFailure
        if ($probe.ExitCode -eq 0) {
            return [pscustomobject]@{ Command = $command.Source; Prefix = $prefix }
        }
    }
    throw 'No se encontró Python 3 para ejecutar scripts/validate_public_repo.py.'
}

function Assert-SafeReleaseNotes {
    param([Parameter(Mandatory = $true)][string]$Path)

    $content = [System.IO.File]::ReadAllText($Path)
    if ([string]::IsNullOrWhiteSpace($content)) {
        throw 'El archivo de notas está vacío.'
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
            throw 'Las notas parecen contener una credencial, token o clave privada. El valor detectado no se mostrará.'
        }
    }
    return $content
}

function Assert-ReleaseHistory {
    param(
        [string]$Gh,
        [string]$Slug,
        [int]$RequestedBuildNumber
    )

    $listResult = Invoke-Native -Command $Gh -Arguments @('release', 'list', '--repo', $Slug, '--limit', '1000', '--json', 'tagName,isDraft') -FailureMessage 'No se pudo consultar el historial de Releases'
    $releases = @()
    $json = ($listResult.Output -join "`n").Trim()
    if ($json) { $releases = @(ConvertFrom-Json $json) }

    $highestBuildNumber = 0
    foreach ($release in $releases) {
        if ($release.isDraft) { continue }
        $viewResult = Invoke-Native -Command $Gh -Arguments @('release', 'view', $release.tagName, '--repo', $Slug, '--json', 'body,assets') -FailureMessage "No se pudo inspeccionar la Release $($release.tagName)"
        $details = ConvertFrom-Json (($viewResult.Output -join "`n"))
        $hasApk = @($details.assets | Where-Object { $_.name -like '*.apk' }).Count -gt 0
        if (-not $hasApk) { continue }
        $buildMatch = [regex]::Match([string]$details.body, '(?im)^Android build number:\s*([1-9][0-9]*)\s*$')
        if (-not $buildMatch.Success) {
            throw "La Release $($release.tagName) contiene un APK sin 'Android build number'. Documentalo antes de continuar para poder verificar versionCode."
        }
        $existingBuildNumber = [int]$buildMatch.Groups[1].Value
        if ($existingBuildNumber -gt $highestBuildNumber) { $highestBuildNumber = $existingBuildNumber }
    }
    if ($RequestedBuildNumber -le $highestBuildNumber) {
        throw "BuildNumber debe ser mayor que el último Android versionCode publicado ($highestBuildNumber)."
    }
}

$originalLocation = Get-Location
$releaseSucceeded = $false
$stageDirectory = $null

try {
    if ($Owner -notmatch '^[A-Za-z0-9_.-]+$' -or $Repository -notmatch '^[A-Za-z0-9_.-]+$' -or
        $Owner -in @('.', '..') -or $Repository -in @('.', '..')) {
        throw 'Owner y Repository deben ser nombres simples válidos de GitHub.'
    }
    $slug = "$Owner/$Repository"

    $publicRoot = Get-CanonicalPath $PSScriptRoot
    Set-Location -LiteralPath $publicRoot
    $appRoot = Get-CanonicalPath $AppRepository
    $appDirectory = Join-Path $appRoot 'app'

    $comparison = [System.StringComparison]::OrdinalIgnoreCase
    $publicPrefix = $publicRoot + [System.IO.Path]::DirectorySeparatorChar
    if ($appRoot.Equals($publicRoot, $comparison) -or $appRoot.StartsWith($publicPrefix, $comparison)) {
        throw 'El repositorio privado no puede estar dentro del repositorio beta público.'
    }

    foreach ($requiredPath in @(
        (Join-Path $appRoot 'app\pubspec.yaml'),
        (Join-Path $appRoot 'app\lib\main.dart'),
        (Join-Path $appRoot 'app\android'),
        (Join-Path $appRoot 'app\android\app')
    )) {
        if (-not (Test-Path -LiteralPath $requiredPath)) {
            throw "El repositorio privado no tiene la estructura Flutter/Android esperada: falta $requiredPath"
        }
    }
    $pubspecContent = [System.IO.File]::ReadAllText((Join-Path $appDirectory 'pubspec.yaml'))
    if ($pubspecContent -notmatch '(?m)^\s*flutter:\s*$' -and $pubspecContent -notmatch 'sdk:\s*flutter') {
        throw 'app/pubspec.yaml no parece pertenecer a un proyecto Flutter.'
    }
    $releaseMetadata = Get-FlutterReleaseMetadata (Join-Path $appDirectory 'pubspec.yaml')
    $Version = $releaseMetadata.Version
    $BuildNumber = $releaseMetadata.BuildNumber
    $versionCore = $Version
    $tag = "v$Version"
    $assetName = "giramesa-$Version.apk"
    $checksumName = "$assetName.sha256"
    $isPrerelease = $Prerelease.IsPresent -or $Version.Contains('-')
    Write-Status "Flutter pubspec: versión $Version, build $BuildNumber, tag $tag"

    $git = Get-CommandPath 'git'
    $flutter = Get-CommandPath 'flutter'
    $gh = Get-CommandPath 'gh'
    $java = Get-CommandPath 'java'
    $python = Get-PythonCommand
    $apkSigner = Find-ApkSigner $ApkSignerPath
    Invoke-Native -Command $java -Arguments @('-version') -FailureMessage 'Java no está operativo' | Out-Null

    $privateRootResult = Invoke-Native -Command $git -Arguments @('-C', $appRoot, 'rev-parse', '--show-toplevel') -FailureMessage 'AppRepository no es un repositorio Git válido'
    $privateGitRoot = ($privateRootResult.Output -join "`n").Trim().TrimEnd('\', '/')
    if (-not $privateGitRoot.Equals($appRoot, $comparison)) {
        throw 'AppRepository debe apuntar exactamente a la raíz del repositorio privado.'
    }

    $rootResult = Invoke-Native -Command $git -Arguments @('rev-parse', '--show-toplevel') -FailureMessage 'Este directorio no es un repositorio Git'
    $gitRoot = ($rootResult.Output -join "`n").Trim().TrimEnd('\', '/')
    if (-not $gitRoot.Equals($publicRoot, $comparison)) {
        throw 'El script debe ejecutarse desde la raíz del repositorio giramesa-beta.'
    }
    $branchResult = Invoke-Native -Command $git -Arguments @('branch', '--show-current') -FailureMessage 'No se pudo determinar la rama actual'
    if (($branchResult.Output -join '').Trim() -ne 'main') {
        throw "La publicación exige la rama main. Cambiá de rama manualmente; el script no lo hará."
    }
    $originResult = Invoke-Native -Command $git -Arguments @('remote', 'get-url', 'origin') -FailureMessage 'Falta el remoto origin'
    $expectedOrigin = "https://github.com/$Owner/$Repository.git"
    if (-not (($originResult.Output -join '').Trim().TrimEnd('/')).Equals($expectedOrigin, $comparison)) {
        throw "origin no coincide con el repositorio público esperado: $expectedOrigin"
    }
    $statusResult = Invoke-Native -Command $git -Arguments @('status', '--porcelain=v1', '--untracked-files=all') -FailureMessage 'No se pudo comprobar el estado Git'
    if (($statusResult.Output -join '').Trim()) {
        throw 'El worktree o el índice público tiene cambios. Resolvelos manualmente antes de publicar.'
    }

    $trackedResult = Invoke-Native -Command $git -Arguments @('ls-files') -FailureMessage 'No se pudo auditar el índice Git'
    $forbiddenPattern = '(?i)(\.apk|\.aab|\.apks|\.ipa|\.jks|\.keystore|\.p12|\.pfx|\.cer|\.pem|\.key|\.mobileprovision|\.provisionprofile)$'
    if (@($trackedResult.Output | Where-Object { $_ -match $forbiddenPattern }).Count -gt 0) {
        throw 'El índice contiene un binario móvil o material de firma prohibido. Retiralo sin mover material privado a este repositorio.'
    }
    $ignoreResult = Invoke-Native -Command $git -Arguments @('check-ignore', '--quiet', '.release-work/probe.apk') -AllowFailure
    if ($ignoreResult.ExitCode -ne 0) {
        throw '.release-work/ debe estar ignorado por Git antes de compilar o copiar artefactos.'
    }

    $authResult = Invoke-Native -Command $gh -Arguments @('auth', 'status') -AllowFailure
    if ($authResult.ExitCode -ne 0) {
        throw "GitHub CLI no está autenticado. Ejecutá 'gh auth login' por separado; este script nunca solicita ni almacena tokens."
    }
    $repoResult = Invoke-Native -Command $gh -Arguments @('repo', 'view', $slug, '--json', 'nameWithOwner,visibility,url,defaultBranchRef') -FailureMessage "No se pudo consultar $slug"
    $repoData = ConvertFrom-Json (($repoResult.Output -join "`n"))
    if (-not ([string]$repoData.nameWithOwner).Equals($slug, $comparison) -or $repoData.visibility -ne 'PUBLIC') {
        throw "$slug no existe o no es PUBLIC. La publicación se canceló."
    }
    if (-not $repoData.defaultBranchRef -or $repoData.defaultBranchRef.name -ne 'main') {
        throw 'La rama predeterminada pública debe ser main.'
    }

    $headResult = Invoke-Native -Command $git -Arguments @('rev-parse', 'HEAD') -FailureMessage 'No se pudo leer HEAD'
    $remoteMainResult = Invoke-Native -Command $git -Arguments @('ls-remote', '--heads', 'origin', 'refs/heads/main') -FailureMessage 'No se pudo consultar origin/main'
    $remoteMainLine = ($remoteMainResult.Output -join "`n").Trim()
    if (-not $remoteMainLine) { throw 'origin/main no existe.' }
    $remoteMainHash = ($remoteMainLine -split '\s+')[0]
    if (($headResult.Output -join '').Trim() -ne $remoteMainHash) {
        throw 'main local no coincide con origin/main. Sincronizá manualmente; el script no hace pull, merge ni cambia ramas.'
    }

    $localTagResult = Invoke-Native -Command $git -Arguments @('show-ref', '--verify', '--quiet', "refs/tags/$tag") -AllowFailure
    if ($localTagResult.ExitCode -eq 0) { throw "El tag local $tag ya existe y no se reutilizará." }
    $remoteTagResult = Invoke-Native -Command $git -Arguments @('ls-remote', '--tags', 'origin', "refs/tags/$tag", "refs/tags/$tag^{}") -FailureMessage 'No se pudieron consultar tags remotos'
    if (($remoteTagResult.Output -join '').Trim()) { throw "El tag remoto $tag ya existe y no se reutilizará." }
    $releaseLookup = Invoke-Native -Command $gh -Arguments @('api', "repos/$slug/releases/tags/$tag") -AllowFailure
    if ($releaseLookup.ExitCode -eq 0) { throw "La GitHub Release $tag ya existe y no se sobrescribirá." }
    if (($releaseLookup.Output -join "`n") -notmatch '(?i)404|not found') {
        throw "No se pudo confirmar que la Release $tag esté libre. Revisá conectividad y permisos."
    }
    Assert-ReleaseHistory -Gh $gh -Slug $slug -RequestedBuildNumber $BuildNumber

    $releaseNotesContent = $null
    $resolvedNotesPath = $null
    if ($ReleaseNotesFile) {
        if (-not (Test-Path -LiteralPath $ReleaseNotesFile -PathType Leaf)) {
            throw "No existe el archivo de notas: $ReleaseNotesFile"
        }
        $resolvedNotesPath = (Resolve-Path -LiteralPath $ReleaseNotesFile).Path
        $releaseNotesContent = Assert-SafeReleaseNotes $resolvedNotesPath
    } elseif (-not $WhatIfPreference) {
        $confirmed = $PSCmdlet.ShouldContinue(
            'No se indicó -ReleaseNotesFile. Se generará una plantilla neutral que debés revisar en la Release.',
            'Generar notas temporales'
        )
        if (-not $confirmed) { throw 'Publicación cancelada: se requieren notas de versión.' }
        $releaseNotesContent = "## Qué probar`r`n- Validar los flujos principales de esta versión.`r`n`r`n## Cambios visibles`r`n- Versión de prueba para validación.`r`n`r`n## Problemas conocidos`r`n- Sin problemas conocidos documentados.`r`n"
    } else {
        Write-Status 'WhatIf: se pediría confirmación explícita para generar notas temporales.'
    }

    if ($ApiBaseUrl) { Assert-PublicHttpsUrl $ApiBaseUrl }

    $stageDirectory = Join-Path $publicRoot ".release-work\$Version"
    $stagedApk = Join-Path $stageDirectory $assetName
    $checksumFile = Join-Path $stageDirectory $checksumName
    $publicationNotes = Join-Path $stageDirectory 'release-notes.md'
    $sourceApk = Join-Path $appDirectory 'build\app\outputs\flutter-apk\app-release.apk'

    $flutterBuildArguments = @('build', 'apk', '--release', '--build-name', $versionCore, '--build-number', "$BuildNumber")
    if ($ApiBaseUrl) { $flutterBuildArguments += "--dart-define=API_BASE_URL=$ApiBaseUrl" }

    if ($WhatIfPreference) {
        $PSCmdlet.ShouldProcess($appDirectory, 'Ejecutar flutter pub get, pruebas y compilación APK release') | Out-Null
        Write-Status 'WhatIf: flutter pub get'
        if ($SkipTests) { Write-Status 'WhatIf: flutter test se omitiría por -SkipTests.' } else { Write-Status 'WhatIf: flutter test' }
        $safeBuildDisplay = "flutter build apk --release --build-name $versionCore --build-number $BuildNumber"
        if ($ApiBaseUrl) { $safeBuildDisplay += ' --dart-define=API_BASE_URL=<url-https-publica-validada>' }
        Write-Status "WhatIf: $safeBuildDisplay"
        $PSCmdlet.ShouldProcess($stageDirectory, "Crear $assetName, checksum y notas locales") | Out-Null
        $PSCmdlet.ShouldProcess("GitHub $slug", "Crear Release $tag en main y subir APK + checksum") | Out-Null
        Write-Status 'WhatIf completado: no se compiló, creó, subió ni modificó ningún artefacto.'
        Write-Status 'iPhone no está incluido: TestFlight requiere un flujo separado en macOS/App Store Connect.'
        return
    }

    if (-not $PSCmdlet.ShouldProcess($appDirectory, 'Ejecutar flutter pub get, pruebas y compilación APK release')) { return }
    Push-Location -LiteralPath $appDirectory
    try {
        Invoke-Native -Command $flutter -Arguments @('pub', 'get') -FailureMessage 'flutter pub get ha fallado' -ShowOutput -DisplayCommand 'flutter pub get' | Out-Null
        if (-not $SkipTests) {
            Invoke-Native -Command $flutter -Arguments @('test') -FailureMessage 'flutter test ha fallado' -ShowOutput -DisplayCommand 'flutter test' | Out-Null
        }
        $buildStartedAt = [DateTime]::UtcNow.AddSeconds(-2)
        $safeBuildDisplay = "flutter build apk --release --build-name $versionCore --build-number $BuildNumber"
        if ($ApiBaseUrl) { $safeBuildDisplay += ' --dart-define=API_BASE_URL=<url-https-publica-validada>' }
        Invoke-Native -Command $flutter -Arguments $flutterBuildArguments -FailureMessage 'La compilación APK release ha fallado; revisá la salida local de Flutter sin exponer ApiBaseUrl' -DisplayCommand $safeBuildDisplay | Out-Null
        Write-Status 'Compilación APK release completada.'
    } finally {
        Pop-Location
    }
    if (-not (Test-Path -LiteralPath $sourceApk -PathType Leaf)) {
        throw "Flutter no generó el APK release esperado: $sourceApk"
    }
    if ((Get-Item -LiteralPath $sourceApk).LastWriteTimeUtc -lt $buildStartedAt) {
        throw 'El APK encontrado es anterior a esta compilación; se evita publicar un artefacto obsoleto.'
    }

    if (-not $PSCmdlet.ShouldProcess($stageDirectory, "Crear $assetName, checksum y notas locales")) { return }
    New-Item -ItemType Directory -Path $stageDirectory -Force | Out-Null
    Copy-Item -LiteralPath $sourceApk -Destination $stagedApk

    $signerResult = Invoke-Native -Command $apkSigner -Arguments @('verify', '--verbose', '--print-certs', $stagedApk) -FailureMessage 'apksigner rechazó la firma del APK'
    $signerOutput = $signerResult.Output -join "`n"
    if ($signerOutput -match '(?i)CN\s*=\s*Android Debug|Android Debug') {
        throw 'El APK está firmado con el certificado Android Debug y no puede publicarse.'
    }
    $digestMatch = [regex]::Match($signerOutput, '(?im)certificate SHA-256 digest:\s*([0-9a-f]{64})')
    if ($digestMatch.Success) {
        Write-Status "Firma release verificada. SHA-256 público del certificado: $($digestMatch.Groups[1].Value.ToLowerInvariant())"
    } else {
        Write-Status 'Firma release verificada; no se imprimen datos privados de firma.'
    }

    $hash = (Get-FileHash -LiteralPath $stagedApk -Algorithm SHA256).Hash.ToLowerInvariant()
    [System.IO.File]::WriteAllText($checksumFile, "$hash  $assetName`n", (New-Object System.Text.UTF8Encoding($false)))
    $notesWithMetadata = $releaseNotesContent.TrimEnd() + "`r`n`r`nAndroid build number: $BuildNumber`r`nSHA-256: $hash`r`n"
    [System.IO.File]::WriteAllText($publicationNotes, $notesWithMetadata, (New-Object System.Text.UTF8Encoding($false)))

    if ((Split-Path -Leaf $stagedApk) -ne $assetName -or $assetName -notmatch '^giramesa-[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?\.apk$') {
        throw 'El nombre final del APK no cumple la convención pública.'
    }
    $validatorArguments = @($python.Prefix) + @((Join-Path $publicRoot 'scripts\validate_public_repo.py'))
    Invoke-Native -Command $python.Command -Arguments $validatorArguments -FailureMessage 'El validador del repositorio público ha fallado' -ShowOutput -DisplayCommand 'python scripts/validate_public_repo.py' | Out-Null
    $postStageStatus = Invoke-Native -Command $git -Arguments @('status', '--porcelain=v1', '--untracked-files=all') -FailureMessage 'No se pudo comprobar Git después del staging'
    if (($postStageStatus.Output -join '').Trim()) {
        throw 'El staging local modificó el worktree o el índice. No se publicará ningún binario.'
    }

    $releaseArguments = @('release', 'create', $tag, $stagedApk, $checksumFile, '--repo', $slug, '--target', 'main', '--title', "Giramesa $Version", '--notes-file', $publicationNotes)
    if ($isPrerelease) { $releaseArguments += '--prerelease' }
    if (-not $PSCmdlet.ShouldProcess("GitHub $slug", "Crear Release $tag en main y subir APK + checksum")) { return }
    Invoke-Native -Command $gh -Arguments $releaseArguments -FailureMessage 'No se pudo crear la GitHub Release' -ShowOutput -DisplayCommand "gh release create $tag <apk> <checksum> --repo $slug --target main" | Out-Null

    $verifyResult = Invoke-Native -Command $gh -Arguments @('release', 'view', $tag, '--repo', $slug, '--json', 'url,tagName,isPrerelease,assets') -FailureMessage 'La Release se creó pero no pudo verificarse'
    $published = ConvertFrom-Json (($verifyResult.Output -join "`n"))
    $publishedAssets = @($published.assets | ForEach-Object { $_.name })
    if ($published.tagName -ne $tag -or [bool]$published.isPrerelease -ne $isPrerelease -or
        $assetName -notin $publishedAssets -or $checksumName -notin $publishedAssets) {
        throw 'La verificación remota no encontró el tag o los dos assets esperados. Los artefactos locales se conservarán.'
    }
    $releaseSucceeded = $true
    Write-Status "Release pública verificada: $($published.url)"
    Write-Status "Portal público: https://$Owner.github.io/$Repository/"
    Write-Status 'iPhone no está incluido: TestFlight requiere un flujo separado en macOS/App Store Connect.'
} catch {
    Write-Error $_.Exception.Message -ErrorAction Continue
    if ($stageDirectory -and (Test-Path -LiteralPath $stageDirectory)) {
        Write-Status "Se conservan artefactos locales ignorados para diagnóstico: $stageDirectory"
    }
    exit 1
} finally {
    if ($releaseSucceeded -and -not $KeepArtifacts -and $stageDirectory -and (Test-Path -LiteralPath $stageDirectory)) {
        if ($PSCmdlet.ShouldProcess($stageDirectory, 'Eliminar artefactos locales ya publicados')) {
            Remove-Item -LiteralPath $stageDirectory -Recurse -Force
            Write-Status 'Artefactos locales eliminados; los assets permanecen en GitHub Releases.'
        }
    } elseif ($releaseSucceeded -and $KeepArtifacts) {
        Write-Status "Artefactos conservados por -KeepArtifacts en: $stageDirectory"
    }
    Set-Location -LiteralPath $originalLocation
}
