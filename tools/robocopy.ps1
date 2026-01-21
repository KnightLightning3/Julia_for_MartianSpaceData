$source = "E:\maven"
$dest = "F:\maven"
$threshold = 104857600 # 100MB

# --- 1. 获取所有待处理文件并分流 ---
Write-Host "正在扫描文件并进行大小分流..." -ForegroundColor Cyan

# 获取所有文件（排除目录）
$allFiles = Get-ChildItem -Path $source -Recurse | Where-Object { !$_.PSIsContainer }

# 分成两组：大文件和小文件
$largeFiles = $allFiles | Where-Object { $_.Length -ge $threshold }
$smallFiles = $allFiles | Where-Object { $_.Length -lt $threshold }

$totalLarge = ($largeFiles | Measure-Object).Count
$totalSmall = ($smallFiles | Measure-Object).Count

Write-Host "扫描完成：" -ForegroundColor White
Write-Host "  - 小文件 (<100MB): $totalSmall 个 (将开启 MT:4 传输)" -ForegroundColor Green
Write-Host "  - 大文件 (>=100MB): $totalLarge 个 (将开启 /J 直接IO传输)" -ForegroundColor Yellow
Write-Host "--------------------------------------------"

# --- 2. 处理小文件 (分块多线程处理以提高效率) ---
if ($totalSmall -gt 0) {
    Write-Host "正在通过 MT:4 传输小文件..." -ForegroundColor Green
    # 注意：小文件我们不需要循环执行，直接交给 robocopy 过滤大小并开启多线程更高效
    robocopy $source $dest /E /MT:4 /MAX:($threshold - 1) /W:1 /R:1 /NP /NJH /NJS /NDL /NFL
}

# --- 3. 处理大文件 (循环执行并显示进度) ---
if ($totalLarge -gt 0) {
    Write-Host "`n正在通过 /J 模式传输大文件..." -ForegroundColor Yellow
    $currentCount = 0
    
    foreach ($file in $largeFiles) {
        $currentCount++
        $relative = $file.FullName.Replace($source, "")
        $targetPath = Join-Path $dest $relative
        $targetDir = Split-Path $targetPath
        
        # 显示进度条
        $percent = [Math]::Round(($currentCount / $totalLarge) * 100, 1)
        Write-Progress -Activity "同步大文件 (Mode: /J)" -Status "进度: $currentCount / $totalLarge ($percent%)" -PercentComplete $percent
        
        # 实时显示当前文件名
        Write-Host "`r正在传输 ($currentCount/$totalLarge): $($file.Name)" -NoNewline
        
        # 执行大文件专用 Robocopy 逻辑
        robocopy $file.DirectoryName $targetDir $file.Name /MT:1 /J /W:1 /R:1 /NP /NJH /NJS /NDL /NFL > $null
    }
}

Write-Host "`n`n✅ 所有任务已完成！" -ForegroundColor Cyan