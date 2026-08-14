[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [Parameter()]
    [ValidatePattern('^[A-Za-z0-9_.-]+$')]
    [string]$Owner = 'wertyMSD',

    [Parameter()]
    [ValidatePattern('^[A-Za-z0-9_.-]+$')]
    [string]$Repository = 'giramesa-beta',

    [Parameter()]
    [ValidateNotNullOrEmpty()]
    [string]$CommitMessage = 'chore: publish Giramesa beta portal',

    [Parameter()]
    [switch]$SkipPages,

    [Parameter()]
    [switch]$InstallGitHubCli
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Status {
    param([Parameter(Mandatory = $true)][string]$Message)

    Write-Host "[Giramesa] $Message"
}

function Invoke-NativeCommand {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter()][string[]]$Arguments = @(),
        [Parameter(Mandatory = $true)][string]$FailureMessage
    )

    & $FilePath @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$FailureMessage (código $LASTEXITCODE)."
    }
}

function Invoke-NativeCapture {
    param(
        [Parameter(Mandatory = $true)][string]$FilePath,
        [Parameter()][string[]]$Arguments = @()
    )

    $output = @(& $FilePath @Arguments 2>&1)
    $exitCode = $LASTEXITCODE
    [PSCustomObject]@{
        ExitCode = $exitCode
        Output = @($output | ForEach-Object { $_.ToString() })
        Text = ($output | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
    }
}

function Resolve-CommandPath {
    param([Parameter(Mandatory = $true)][string]$Name)

    $command = Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($null -eq $command) {
        return $null
    }
    return $command.Source
}

function Resolve-GitHubCliPath {
    $resolved = Resolve-CommandPath -Name 'gh'
    if ($null -ne $resolved) {
        return $resolved
    }

    $candidates = @(
        (Join-Path $env:ProgramFiles 'GitHub CLI\gh.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\GitHub CLI\gh.exe')
    )
    if (-not [string]::IsNullOrWhiteSpace(${env:ProgramFiles(x86)})) {
        $candidates += Join-Path ${env:ProgramFiles(x86)} 'GitHub CLI\gh.exe'
    }

    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return (Resolve-Path -LiteralPath $candidate).Path
        }
    }
    return $null
}

function Get-GitPaths {
    param(
        [Parameter(Mandatory = $true)][string]$GitPath,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    $result = Invoke-NativeCapture -FilePath $GitPath -Arguments $Arguments
    if ($result.ExitCode -ne 0) {
        throw 'No se pudieron inspeccionar las rutas de Git.'
    }
    return @($result.Output | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function Assert-SafePublicPaths {
    param([Parameter(Mandatory = $true)][string[]]$Paths)

    $unsafe = @()
    $forbiddenExtensions = @(
        '.apk', '.aab', '.apks', '.ipa', '.jks', '.keystore', '.p12', '.pfx',
        '.cer', '.crt', '.der', '.pem', '.key', '.mobileprovision',
        '.provisionprofile', '.asc', '.gpg'
    )

    foreach ($path in $Paths) {
        $normalized = $path.Replace('\', '/').ToLowerInvariant()
        $fileName = [IO.Path]::GetFileName($normalized)
        $extension = [IO.Path]::GetExtension($fileName)

        $isEnvironmentFile = $normalized -match '(^|/)\.env(?:\.|$)'
        $isServiceCredential = (
            $fileName -eq 'google-services.json' -or
            $fileName -eq 'googleservice-info.plist' -or
            $fileName -match '^service-account.*\.json$' -or
            $fileName -match '^(?:credentials?|firebase-adminsdk).*\.json$'
        )
        $hasSensitiveName = $normalized -match '(^|/)(?:secrets?|tokens?|passwords?|private[_-]?keys?|id_rsa|id_dsa)(?:[._/-]|$)'

        if ($forbiddenExtensions -contains $extension -or $isEnvironmentFile -or $isServiceCredential -or $hasSensitiveName) {
            $unsafe += $path
        }
    }

    if ($unsafe.Count -gt 0) {
        throw "Publicación bloqueada: hay $($unsafe.Count) ruta(s) staged con nombres de artefactos, firma, entorno o credenciales. No se muestran sus nombres."
    }
}

function Test-GitHubNotFound {
    param([Parameter(Mandatory = $true)][string]$Text)

    return $Text -match '(?i)(HTTP\s+404|not found)'
}

$repoRoot = (Resolve-Path -LiteralPath $PSScriptRoot).Path
$slug = "$Owner/$Repository"
$expectedRemote = "https://github.com/$slug.git"

Write-Status 'Este proceso publica solamente el repositorio del portal.'
Write-Status 'No compila, firma ni sube APK; tampoco configura Apple ni TestFlight.'

Push-Location -LiteralPath $repoRoot
try {
    $gitPath = Resolve-CommandPath -Name 'git'
    if ($null -eq $gitPath) {
        throw 'Git no está disponible en PATH.'
    }

    $gitRootResult = Invoke-NativeCapture -FilePath $gitPath -Arguments @('rev-parse', '--show-toplevel')
    if ($gitRootResult.ExitCode -ne 0 -or $gitRootResult.Output.Count -eq 0) {
        throw 'El script debe ejecutarse dentro del repositorio standalone de Giramesa Beta.'
    }
    $gitRoot = [IO.Path]::GetFullPath($gitRootResult.Output[-1]).TrimEnd('\', '/')
    $normalizedRoot = [IO.Path]::GetFullPath($repoRoot).TrimEnd('\', '/')
    if (-not $gitRoot.Equals($normalizedRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'El script debe estar en la raíz del repositorio standalone, no en un repositorio padre.'
    }

    $requiredMarkers = @(
        'README.md',
        'docs\index.html',
        'scripts\validate_public_repo.py',
        '.github\workflows\pages.yml'
    )
    foreach ($marker in $requiredMarkers) {
        if (-not (Test-Path -LiteralPath (Join-Path $repoRoot $marker) -PathType Leaf)) {
            throw "Falta el marcador requerido del repositorio standalone: $marker"
        }
    }

    $nestedSourceMarkers = @(
        'lib\main.dart',
        'android\app',
        'ios\Runner',
        'app\lib',
        'backend\app'
    )
    foreach ($marker in $nestedSourceMarkers) {
        if (Test-Path -LiteralPath (Join-Path $repoRoot $marker)) {
            throw 'Publicación bloqueada: se detectó código fuente anidado de la aplicación.'
        }
    }
    $pubspec = Get-ChildItem -LiteralPath $repoRoot -Filter 'pubspec.yaml' -File -Recurse -ErrorAction Stop |
        Select-Object -First 1
    if ($null -ne $pubspec) {
        throw 'Publicación bloqueada: se detectó un proyecto Flutter anidado.'
    }

    $pythonPath = $null
    $pythonPrefix = @()
    $pyLauncher = Resolve-CommandPath -Name 'py'
    if ($null -ne $pyLauncher) {
        $pyCheck = Invoke-NativeCapture -FilePath $pyLauncher -Arguments @('-3', '--version')
        if ($pyCheck.ExitCode -eq 0) {
            $pythonPath = $pyLauncher
            $pythonPrefix = @('-3')
        }
    }
    if ($null -eq $pythonPath) {
        $pythonPath = Resolve-CommandPath -Name 'python'
    }
    if ($null -eq $pythonPath) {
        throw 'Python 3 no está disponible mediante py -3 ni python.'
    }

    $pythonVersion = Invoke-NativeCapture -FilePath $pythonPath -Arguments ($pythonPrefix + @('--version'))
    if ($pythonVersion.ExitCode -ne 0 -or $pythonVersion.Text -notmatch 'Python 3\.') {
        throw 'El intérprete encontrado no es Python 3.'
    }

    $ghPath = Resolve-GitHubCliPath
    if ($null -eq $ghPath) {
        $installCommand = 'winget install --id GitHub.cli -e'
        if (-not $InstallGitHubCli) {
            Write-Host $installCommand
            Write-Status 'GitHub CLI no está instalado. Ejecutá el comando anterior o repetí con -InstallGitHubCli.'
            return
        }

        $wingetPath = Resolve-CommandPath -Name 'winget'
        if ($null -eq $wingetPath) {
            throw "winget no está disponible. Instalá GitHub CLI manualmente con: $installCommand"
        }
        if ($PSCmdlet.ShouldProcess('GitHub CLI', "Instalar con '$installCommand'")) {
            Invoke-NativeCommand -FilePath $wingetPath -Arguments @('install', '--id', 'GitHub.cli', '-e') -FailureMessage 'No se pudo instalar GitHub CLI'
        }
        else {
            Write-Status "Simulación: $installCommand"
            return
        }

        $ghPath = Resolve-GitHubCliPath
        if ($null -eq $ghPath) {
            throw 'GitHub CLI se instaló, pero gh.exe no se encontró. Abrí una consola nueva y repetí el comando.'
        }
    }

    Write-Status 'Ejecutando pruebas y validación pública antes de staging.'
    Invoke-NativeCommand -FilePath $pythonPath -Arguments ($pythonPrefix + @('-m', 'unittest', 'discover', '-s', 'tests', '-v')) -FailureMessage 'Fallaron las pruebas'
    Invoke-NativeCommand -FilePath $pythonPath -Arguments ($pythonPrefix + @('scripts/validate_public_repo.py')) -FailureMessage 'Falló la validación del repositorio público'

    $stagingPerformed = $false
    if ($PSCmdlet.ShouldProcess($repoRoot, 'Stagear todos los cambios con git add --all')) {
        Invoke-NativeCommand -FilePath $gitPath -Arguments @('add', '--all') -FailureMessage 'No se pudieron stagear los cambios'
        $stagingPerformed = $true
        $candidatePaths = Get-GitPaths -GitPath $gitPath -Arguments @('diff', '--cached', '--name-only')
    }
    else {
        Write-Status 'Simulación: staging omitido; se inspeccionan las rutas que se stagearían.'
        $candidatePaths = @(
            Get-GitPaths -GitPath $gitPath -Arguments @('diff', '--cached', '--name-only')
            Get-GitPaths -GitPath $gitPath -Arguments @('diff', '--name-only')
            Get-GitPaths -GitPath $gitPath -Arguments @('ls-files', '--others', '--exclude-standard')
        ) | Sort-Object -Unique
    }
    Assert-SafePublicPaths -Paths @($candidatePaths)
    Write-Status "Inspección segura completada para $(@($candidatePaths).Count) ruta(s)."

    $stagedPaths = Get-GitPaths -GitPath $gitPath -Arguments @('diff', '--cached', '--name-only')
    $hasChangesToCommit = $stagedPaths.Count -gt 0
    if (-not $stagingPerformed -and $WhatIfPreference -and @($candidatePaths).Count -gt 0) {
        $hasChangesToCommit = $true
    }

    if ($hasChangesToCommit) {
        if ($PSCmdlet.ShouldProcess($repoRoot, "Crear commit '$CommitMessage'")) {
            Invoke-NativeCommand -FilePath $gitPath -Arguments @('commit', '-m', $CommitMessage) -FailureMessage 'No se pudo crear el commit'
        }
    }
    else {
        Write-Status 'No hay cambios staged; se continúa de forma idempotente.'
    }

    $branchResult = Invoke-NativeCapture -FilePath $gitPath -Arguments @('branch', '--show-current')
    if ($branchResult.ExitCode -ne 0 -or $branchResult.Text.Trim() -ne 'main') {
        throw 'La rama activa debe ser main antes de publicar.'
    }

    $authStatus = Invoke-NativeCapture -FilePath $ghPath -Arguments @('auth', 'status', '--hostname', 'github.com')
    $authenticationReady = $authStatus.ExitCode -eq 0
    if (-not $authenticationReady) {
        if ($PSCmdlet.ShouldProcess('github.com', 'Iniciar autenticación web interactiva de GitHub CLI')) {
            Invoke-NativeCommand -FilePath $ghPath -Arguments @('auth', 'login', '--hostname', 'github.com', '--git-protocol', 'https', '--web') -FailureMessage 'No se completó la autenticación con GitHub'
            $authStatus = Invoke-NativeCapture -FilePath $ghPath -Arguments @('auth', 'status', '--hostname', 'github.com')
            if ($authStatus.ExitCode -ne 0) {
                throw 'GitHub CLI sigue sin estar autenticado.'
            }
            $authenticationReady = $true
        }
        elseif (-not $WhatIfPreference) {
            throw 'GitHub CLI necesita autenticación para continuar.'
        }
    }
    if ($authenticationReady) {
        Write-Status 'GitHub CLI autenticado para github.com.'
    }

    $remoteList = Get-GitPaths -GitPath $gitPath -Arguments @('remote')
    $originExists = @($remoteList) -contains 'origin'
    if ($originExists) {
        $originResult = Invoke-NativeCapture -FilePath $gitPath -Arguments @('remote', 'get-url', 'origin')
        if ($originResult.ExitCode -ne 0 -or $originResult.Output.Count -eq 0) {
            throw 'No se pudo leer la URL de origin.'
        }
        $escapedSlug = [Regex]::Escape($slug)
        $validOrigin = $originResult.Output[-1] -match "(?i)^(?:https://github\.com/|git@github\.com:|ssh://git@github\.com/)$escapedSlug(?:\.git)?/?$"
        if (-not $validOrigin) {
            throw 'origin ya existe y apunta a otro repositorio; no se reemplazará automáticamente.'
        }
    }

    $repositoryExists = $false
    if ($authenticationReady) {
        $repositoryProbe = Invoke-NativeCapture -FilePath $ghPath -Arguments @('api', "repos/$slug", '--jq', '.visibility')
        if ($repositoryProbe.ExitCode -eq 0) {
            $repositoryExists = $true
            if ($repositoryProbe.Text.Trim().ToLowerInvariant() -ne 'public') {
                throw "El repositorio $slug ya existe, pero no es PUBLIC. No se modificará su visibilidad."
            }
            Write-Status "Repositorio público verificado: https://github.com/$slug"
        }
        elseif (-not (Test-GitHubNotFound -Text $repositoryProbe.Text)) {
            throw 'No se pudo verificar si el repositorio remoto existe; no se intentará crearlo.'
        }
    }

    if (-not $repositoryExists) {
        if ($PSCmdlet.ShouldProcess($slug, 'Crear repositorio público en GitHub')) {
            $createArguments = @('repo', 'create', $slug, '--public', '--source', $repoRoot)
            if (-not $originExists) {
                $createArguments += @('--remote', 'origin')
            }
            Invoke-NativeCommand -FilePath $ghPath -Arguments $createArguments -FailureMessage 'No se pudo crear el repositorio público'
            $repositoryExists = $true
            if (-not $originExists) {
                $originExists = $true
            }
        }
    }

    if (-not $originExists) {
        if ($PSCmdlet.ShouldProcess('origin', "Agregar remoto $expectedRemote")) {
            Invoke-NativeCommand -FilePath $gitPath -Arguments @('remote', 'add', 'origin', $expectedRemote) -FailureMessage 'No se pudo agregar origin'
            $originExists = $true
        }
    }

    if ($PSCmdlet.ShouldProcess("origin/main ($slug)", 'Publicar main y configurar upstream')) {
        Invoke-NativeCommand -FilePath $gitPath -Arguments @('push', '--set-upstream', 'origin', 'main') -FailureMessage 'No se pudo publicar main'
    }

    if ($SkipPages) {
        Write-Status 'GitHub Pages omitido por -SkipPages.'
    }
    else {
        $pagesExists = $false
        if ($authenticationReady -and $repositoryExists) {
            $pagesProbe = Invoke-NativeCapture -FilePath $ghPath -Arguments @('api', "repos/$slug/pages", '--jq', '.build_type')
            if ($pagesProbe.ExitCode -eq 0) {
                $pagesExists = $true
                Write-Status "GitHub Pages ya existe (build_type=$($pagesProbe.Text.Trim()))."
            }
            elseif (-not (Test-GitHubNotFound -Text $pagesProbe.Text)) {
                throw 'No se pudo consultar la configuración de GitHub Pages.'
            }
        }

        if (-not $pagesExists -and $PSCmdlet.ShouldProcess($slug, 'Crear GitHub Pages con build_type=workflow')) {
            $pagesCreate = Invoke-NativeCapture -FilePath $ghPath -Arguments @('api', '--method', 'POST', "repos/$slug/pages", '-f', 'build_type=workflow')
            if ($pagesCreate.ExitCode -ne 0 -and $pagesCreate.Text -notmatch '(?i)(HTTP\s+(409|422)|already exists)') {
                throw 'No se pudo crear GitHub Pages.'
            }
            Write-Status 'GitHub Pages preparado para despliegue por workflow.'
        }

        if ($PSCmdlet.ShouldProcess("pages.yml en $slug", 'Ejecutar workflow de GitHub Pages')) {
            Invoke-NativeCommand -FilePath $ghPath -Arguments @('workflow', 'run', 'pages.yml', '--repo', $slug, '--ref', 'main') -FailureMessage 'No se pudo iniciar el workflow de Pages'
        }

        Write-Host "Estado: gh run list --repo $slug --workflow pages.yml"
        Write-Host "Pages API: gh api repos/$slug/pages"
        Write-Host "Acciones: https://github.com/$slug/actions/workflows/pages.yml"
        Write-Host "Portal: https://$Owner.github.io/$Repository/"
    }

    if ($WhatIfPreference) {
        Write-Status 'Simulación completada; no se aplicaron mutaciones.'
    }
    else {
        Write-Status 'Publicación del portal finalizada. Android y Apple requieren procesos separados.'
    }
}
finally {
    Pop-Location
}
