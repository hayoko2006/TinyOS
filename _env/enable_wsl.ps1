$ErrorActionPreference = 'Continue'
$log = 'C:\Users\Administrator\Desktop\tiny\_env\enable_wsl.log'
Start-Transcript -Path $log -Force | Out-Null

Write-Host '=== TinyOS build environment bootstrap ==='
Write-Host 'Enabling Microsoft-Windows-Subsystem-Linux ...'
dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart

Write-Host 'Enabling VirtualMachinePlatform ...'
dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart

Write-Host 'DONE - restart required'
Stop-Transcript | Out-Null
