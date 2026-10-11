$ErrorActionPreference = 'Stop'
$agentsSkills = Join-Path $HOME '.agents\skills'
$claudeSkills = Join-Path $HOME '.claude\skills'
New-Item -ItemType Directory -Force -Path $agentsSkills, $claudeSkills | Out-Null
foreach ($skill in Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'skills') -Directory) {
    $dst = Join-Path $agentsSkills $skill.Name
    $link = Join-Path $claudeSkills $skill.Name
    if (Test-Path -LiteralPath $link) {
        if (((Get-Item -LiteralPath $link -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) { throw "$link existe y no es un enlace: no lo toco" }
        cmd /c rmdir "$link" | Out-Null
    }
    if (Test-Path -LiteralPath $dst) { Remove-Item -LiteralPath $dst -Recurse -Force }
    Copy-Item -LiteralPath $skill.FullName -Destination $dst -Recurse
    New-Item -ItemType Junction -Path $link -Target $dst | Out-Null
    Write-Output "instalado: $($skill.Name)"
}
