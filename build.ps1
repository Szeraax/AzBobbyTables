param(
    [ValidateSet('Debug', 'Release')]
    [string]
    $Configuration = 'Release',

    [string]
    $Version,

    [Switch]
    $NoClean,

    [ValidateSet('All','SkipIntegration','None')]
    $RunTests = 'All'
)

Push-Location 'Source'

$ModuleName = $PSScriptRoot.Split('\')[-1]
$DotNetVersion = 'netstandard2.0'

# Define build output locations
$OutDir = "$PSScriptRoot\out"
$OutDependencies = "$OutDir\dependencies"
$OutDocs = "$OutDir/en-US"

if (Test-Path $OutDir) {
    Remove-Item $OutDir -Recurse -Force -ErrorAction Stop
}

# Build both Core and PS projects
if (-not $NoClean.IsPresent) {
    dotnet build-server shutdown
    dotnet clean -c $Configuration
}
dotnet publish -c $Configuration

# Ensure output directories exist and are clean for build
New-Item -Path $OutDir -ItemType Directory -ErrorAction Ignore
Get-ChildItem $OutDir | Remove-Item -Recurse
New-Item -Path $OutDependencies -ItemType Directory
New-Item -Path $OutDocs -ItemType Directory

# Create array to remember copied files
$CopiedDependencies = @()

# Copy .dll and .pdb files from Core to the dependency directory
Get-ChildItem -Path "$ModuleName.Core\bin\$Configuration\$DotNetVersion\publish" |
Where-Object { $_.Extension -in '.dll', '.pdb' } |
ForEach-Object {
    $CopiedDependencies += $_.Name
    Copy-Item -Path $_.FullName -Destination $OutDependencies
}

# Copy files from PS to output directory, except those already copied from Core
Get-ChildItem -Path "$ModuleName.PS\bin\$Configuration\$DotNetVersion\publish" |
Where-Object { $_.Name -notin $CopiedDependencies -and $_.Extension -in '.dll', '.pdb' } |
ForEach-Object {
    Copy-Item -Path $_.FullName -Destination $OutDir
}

Copy-Item -Path "$ModuleName.PS\Manifest\$ModuleName.psd1" -Destination $OutDir
if (-not $PSBoundParameters.ContainsKey('Version')) {
    try {
        $Version = gitversion /showvariable LegacySemVerPadded
    }
    catch {
        $Version = [string]::Empty
    }
}
if ($Version) {
    $SemVer, $PreReleaseTag = $Version.Split('-')
    Update-ModuleManifest -Path "$OutDir/$ModuleName.psd1" -ModuleVersion $SemVer -Prerelease $PreReleaseTag
}

Pop-Location

# Run markdown file updates and tests in separate PowerShell sessions to avoid module load assembly locking
& pwsh -c "Import-Module '$OutDir\$ModuleName.psd1'; Update-MarkdownHelpModule -Path '$PSScriptRoot\Docs\Help'"
if ($RunTests -ne 'None') {
    & pwsh -c ".\Tests\TestRunner.ps1 -SkipIntegration:`$$($RunTests -eq 'SkipIntegration')"
}

New-ExternalHelp -Path "$PSScriptRoot\Docs\Help" -OutputPath $OutDocs