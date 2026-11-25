# Windows PowerShell 5.1 or later (ASCII-only for PS 5.1 compatibility)
$ErrorActionPreference = 'Stop'
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
$source = 'https://raw.githubusercontent.com/peanutgao/agent-governance/main/scripts'
$state = Join-Path $env:USERPROFILE '.local\share\agent-governance\bootstrap'
$runtime = Join-Path $state 'runtime-win'
$originalPath = $env:Path
$originalMamba = $env:MAMBA_ROOT_PREFIX
$runtimeStage = $null
$temporary = $null

function Assert-Exit([string] $operation) {
    if ($LASTEXITCODE -ne 0) { throw "$operation failed (exit $LASTEXITCODE)." }
}

function Test-RuntimeReady([string] $bashPath) {
    if (!(Test-Path -LiteralPath $bashPath -PathType Leaf)) { return $false }
    $git = Get-Command git.exe -ErrorAction SilentlyContinue
    $python = Get-Command python.exe -ErrorAction SilentlyContinue
    $node = Get-Command node.exe -ErrorAction SilentlyContinue
    $npm = Get-Command npm.cmd -ErrorAction SilentlyContinue
    if (!$git -or !$python -or !$node -or !$npm -or $python.Source -like "$env:LOCALAPPDATA\Microsoft\WindowsApps\*") {
        return $false
    }
    & $python.Source -c 'import sys; sys.exit(sys.version_info < (3, 9))' 2>$null
    if ($LASTEXITCODE -ne 0) { return $false }
    $nodeVersion = & $node.Source -p 'process.versions.node' 2>$null
    $version = $null
    if ($LASTEXITCODE -ne 0 -or ![version]::TryParse($nodeVersion, [ref]$version) -or $version -lt [version]'22.20') {
        return $false
    }
    & $npm.Source --version 2>$null | Out-Null
    return ($LASTEXITCODE -eq 0)
}

function Use-Runtime([string] $prefix) {
    if ($prefix) {
        $env:Path = "$prefix\Library\usr\bin;$prefix\Library\bin;$prefix\Scripts;$prefix;$originalPath"
        $bash = Join-Path $prefix 'Library\usr\bin\bash.exe'
        if (Test-RuntimeReady $bash) { return $bash }
        return $null
    }

    $git = Get-Command git.exe -ErrorAction SilentlyContinue
    if (!$git) { return $null }
    $gitRoot = Split-Path (Split-Path $git.Source)
    $bash = Join-Path $gitRoot 'usr\bin\bash.exe'
    if (!(Test-Path -LiteralPath $bash -PathType Leaf)) { return $null }
    $env:Path = "$gitRoot\usr\bin;$gitRoot\bin;$originalPath"
    if (Test-RuntimeReady $bash) { return $bash }
    $env:Path = $originalPath
    return $null
}

function Resolve-LocalBootstrapScript {
    if (!$PSScriptRoot) { return $null }
    $candidate = Join-Path $PSScriptRoot 'bootstrap.sh'
    $installScript = Join-Path $PSScriptRoot 'install.sh'
    $repoRoot = Split-Path $PSScriptRoot -Parent
    $versionFile = if ($repoRoot) { Join-Path $repoRoot 'VERSION' } else { $null }
    if (
        (Test-Path -LiteralPath $candidate -PathType Leaf) -and
        (Test-Path -LiteralPath $installScript -PathType Leaf) -and
        $versionFile -and
        (Test-Path -LiteralPath $versionFile -PathType Leaf)
    ) {
        return $candidate
    }
    return $null
}

[void](New-Item -ItemType Directory -Path $state -Force)
$lock = [System.IO.File]::Open((Join-Path $state 'windows-runtime.lock'), 'OpenOrCreate', 'ReadWrite', 'None')
try {
    $temporary = Join-Path ([System.IO.Path]::GetTempPath()) ('agent-governance-' + [guid]::NewGuid().ToString('N'))
    [void](New-Item -ItemType Directory -Path $temporary)
    $bash = Use-Runtime ''
    if (!$bash) {
        if (Test-Path -LiteralPath $runtime -PathType Leaf) {
            $savedPrefix = (Get-Content -LiteralPath $runtime -Raw).Trim()
            if ($savedPrefix -notmatch '^runtime-win-[a-f0-9]{32}$') { throw 'Invalid runtime pointer.' }
            $bash = Use-Runtime (Join-Path (Join-Path $state $savedPrefix) 'env')
            if (!$bash) {
                throw "Saved Windows runtime is unavailable or corrupted ($runtime). Remove it and re-run."
            }
        } else {
            $arch = if ($env:PROCESSOR_ARCHITEW6432) { $env:PROCESSOR_ARCHITEW6432 } else { $env:PROCESSOR_ARCHITECTURE }
            switch ($arch) {
                'AMD64' { $target = 'win-64'; $sha = '97a336f4ab794bd96a6a4da5e6ed63e75a1d31830414a182419b23d3b36f3fe0' }
                'ARM64' { $target = 'win-arm64'; $sha = '2a2f41f6bc3e385899d076794f3f9e664fa264aceb08b0a2eb5380eae7411761' }
                default { throw 'Automatic runtime installation requires Windows x64 or ARM64.' }
            }
            $folder = 'runtime-win-' + [guid]::NewGuid().ToString('N')
            $runtimeStage = Join-Path $state $folder
            [void](New-Item -ItemType Directory -Path $runtimeStage)
            $archive = Join-Path $temporary 'micromamba.tar.bz2'
            Write-Host 'Installing Git, Python and Node.js/npm...'
            Invoke-WebRequest -UseBasicParsing -TimeoutSec 120 -Uri "https://conda.anaconda.org/conda-forge/$target/micromamba-2.9.0-0.tar.bz2" -OutFile $archive
            if ((Get-FileHash -Algorithm SHA256 -LiteralPath $archive).Hash -ne $sha) {
                throw 'Runtime installer checksum mismatch.'
            }
            & "$env:SystemRoot\System32\tar.exe" -xjf $archive -C $temporary Library/bin/micromamba.exe
            Assert-Exit 'Runtime installer extraction'
            $env:MAMBA_ROOT_PREFIX = Join-Path $runtimeStage 'cache'
            $prefix = Join-Path $runtimeStage 'env'
            & (Join-Path $temporary 'Library\bin\micromamba.exe') --no-rc create --yes --no-shortcuts --override-channels --channel https://conda.anaconda.org/conda-forge --prefix $prefix git 'python=3.12' 'nodejs=24'
            Assert-Exit 'Runtime installation'
            $bash = Use-Runtime $prefix
            if (!$bash) { throw 'The installed runtime failed verification.' }
            $runtimePointer = Join-Path $runtimeStage 'pointer'
            Set-Content -LiteralPath $runtimePointer -Value $folder -Encoding Ascii
            [System.IO.File]::Move($runtimePointer, $runtime)
            $runtimeStage = $null
        }
    }
    if (!(Test-Path -LiteralPath $bash -PathType Leaf)) { throw 'Git Bash is unavailable.' }

    $launcher = Resolve-LocalBootstrapScript
    if (!$launcher) {
        $launcher = Join-Path $temporary 'bootstrap.sh'
        Invoke-WebRequest -UseBasicParsing -TimeoutSec 120 -Uri "$source/bootstrap.sh" -OutFile $launcher
    }
    $cygpath = Join-Path (Split-Path $bash) 'cygpath.exe'
    $launcherPath = & $cygpath -u $launcher
    Assert-Exit 'Launcher path conversion'
    & $bash --noprofile --norc $launcherPath
    Assert-Exit 'Agent governance deployment'
} finally {
    $env:Path = $originalPath
    $env:MAMBA_ROOT_PREFIX = $originalMamba
    if ($runtimeStage) { Remove-Item -LiteralPath $runtimeStage -Recurse -Force }
    if ($temporary) { Remove-Item -LiteralPath $temporary -Recurse -Force }
    $lock.Dispose()
}
