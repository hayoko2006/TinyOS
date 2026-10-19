# 合并 GitHub Actions 产出的 ISO 分卷（Windows PowerShell）
# 用法:
#   .\join-iso.ps1 -Prefix tinyos-1.0.0-whuang-amd64.iso
#   .\join-iso.ps1 -Prefix tinyos-1.0.0-whuang-amd64.iso -Out D:\tinyos.iso
param(
    [Parameter(Mandatory = $true)][string]$Prefix,
    [string]$Out
)

if (-not $Out) { $Out = $Prefix }

$parts = Get-ChildItem -Path "$Prefix.part-*" | Sort-Object Name
if ($parts.Count -eq 0) {
    Write-Error "未找到分卷文件: $Prefix.part-*"
    exit 1
}

Write-Host "合并 $($parts.Count) 个分卷 -> $Out"
$outPath = [System.IO.Path]::GetFullPath($Out)
$fs = [System.IO.File]::Create($outPath)
try {
    foreach ($p in $parts) {
        $bytes = [System.IO.File]::ReadAllBytes($p.FullName)
        $fs.Write($bytes, 0, $bytes.Length)
    }
}
finally {
    $fs.Close()
}

$hash = (Get-FileHash -Path $outPath -Algorithm SHA256).Hash.ToLower()
Write-Host "SHA256: $hash"

$shaFile = "$Prefix.sha256"
if (Test-Path $shaFile) {
    $expected = (Get-Content $shaFile -Raw).Trim().Split(' ')[0].ToLower()
    if ($expected -eq $hash) {
        Write-Host "  ✓ 校验通过" -ForegroundColor Green
    }
    else {
        Write-Error "  ✗ 校验不匹配（期望 $expected）"
        exit 1
    }
}
