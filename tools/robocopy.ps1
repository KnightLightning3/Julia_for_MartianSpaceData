$source = "E:\MAVEN"
$dest = "D:\MAVEN"

$threshold = 104857600 # 100MB

# --- 1. 获取所有待处理文件并分流 ---
Write-Host "Scaning files via size $threshold bit..." -ForegroundColor Cyan

# 获取所有文件（排除目录）
$allFiles = Get-ChildItem -Path $source -Recurse | Where-Object { !$_.PSIsContainer }

# 分成两组：大文件和小文件
$largeFiles = $allFiles | Where-Object { $_.Length -ge $threshold }
$smallFiles = $allFiles | Where-Object { $_.Length -lt $threshold }

$totalLarge = ($largeFiles | Measure-Object).Count
$totalSmall = ($smallFiles | Measure-Object).Count

Write-Host "Scaning done" -ForegroundColor White
Write-Host "  - small files (<100MB): $totalSmall  (Using MT:4)" -ForegroundColor Green
Write-Host "  - Large files (>=100MB): $totalLarge (Using /J copy via IO)" -ForegroundColor Yellow
Write-Host "--------------------------------------------"

# --- 2. 处理小文件 (分块多线程处理以提高效率) ---
if ($totalSmall -gt 0) {
    Write-Host "Using MT:4 copying small files..." -ForegroundColor Green
    # 注意：小文件我们不需要循环执行，直接交给 robocopy 过滤大小并开启多线程更高效
    robocopy $source $dest /E /MT:4 /MAX:($threshold - 1) /W:1 /R:1 /NP /NJH /NJS /NDL /NFL
}

# --- 3. 处理大文件 (循环执行并显示进度) ---
if ($totalLarge -gt 0) {
    Write-Host "`nUsing /J copying large files..." -ForegroundColor Yellow
    $currentCount = 0
    
    foreach ($file in $largeFiles) {
        $currentCount++
        $relative = $file.FullName.Replace($source, "")
        $targetPath = Join-Path $dest $relative
        $targetDir = Split-Path $targetPath
        
        # 显示进度条
        $percentVal = [Math]::Min(100, [Math]::Round(($currentCount / $totalLarge) * 100, 1))
        Write-Progress -Activity "Syncing Large Files" `
                       -Status "File $currentCount of $totalLarge" `
                       -PercentComplete $percentVal
        
        # 实时显示当前文件名
        Write-Host "`rCopying: [ $currentCount / $totalLarge ] - $($file.Name)" -NoNewline
        
        # 执行大文件专用 Robocopy 逻辑
        robocopy $file.DirectoryName $targetDir $file.Name /MT:1 /J /W:1 /R:1 /NP /NJH /NJS /NDL /NFL > $null
    }
}

Write-Host "`nCopying done" -ForegroundColor Cyan
$source = "E:\MGS"
$dest = "D:\MGS"

$threshold = 104857600 # 100MB

# --- 1. 获取所有待处理文件并分流 ---
Write-Host "Scaning files via size $threshold bit..." -ForegroundColor Cyan

# 获取所有文件（排除目录）
$allFiles = Get-ChildItem -Path $source -Recurse | Where-Object { !$_.PSIsContainer }

# 分成两组：大文件和小文件
$largeFiles = $allFiles | Where-Object { $_.Length -ge $threshold }
$smallFiles = $allFiles | Where-Object { $_.Length -lt $threshold }

$totalLarge = ($largeFiles | Measure-Object).Count
$totalSmall = ($smallFiles | Measure-Object).Count

Write-Host "Scaning done" -ForegroundColor White
Write-Host "  - small files (<100MB): $totalSmall  (Using MT:4)" -ForegroundColor Green
Write-Host "  - Large files (>=100MB): $totalLarge (Using /J copy via IO)" -ForegroundColor Yellow
Write-Host "--------------------------------------------"

# --- 2. 处理小文件 (分块多线程处理以提高效率) ---
if ($totalSmall -gt 0) {
    Write-Host "Using MT:4 copying small files..." -ForegroundColor Green
    # 注意：小文件我们不需要循环执行，直接交给 robocopy 过滤大小并开启多线程更高效
    robocopy $source $dest /E /MT:4 /MAX:($threshold - 1) /W:1 /R:1 /NP /NJH /NJS /NDL /NFL
}

# --- 3. 处理大文件 (循环执行并显示进度) ---
if ($totalLarge -gt 0) {
    Write-Host "`nUsing /J copying large files..." -ForegroundColor Yellow
    $currentCount = 0
    
    foreach ($file in $largeFiles) {
        $currentCount++
        $relative = $file.FullName.Replace($source, "")
        $targetPath = Join-Path $dest $relative
        $targetDir = Split-Path $targetPath
        
        # 显示进度条
        $percentVal = [Math]::Min(100, [Math]::Round(($currentCount / $totalLarge) * 100, 1))
        Write-Progress -Activity "Syncing Large Files" `
                       -Status "File $currentCount of $totalLarge" `
                       -PercentComplete $percentVal
        
        # 实时显示当前文件名
        Write-Host "`rCopying: [ $currentCount / $totalLarge ] - $($file.Name)" -NoNewline
        
        # 执行大文件专用 Robocopy 逻辑
        robocopy $file.DirectoryName $targetDir $file.Name /MT:1 /J /W:1 /R:1 /NP /NJH /NJS /NDL /NFL > $null
    }
}

Write-Host "`nCopying done" -ForegroundColor Cyan
$source = "E:\Tianwen-1"
$dest = "D:\Tianwen-1"

$threshold = 104857600 # 100MB

# --- 1. 获取所有待处理文件并分流 ---
Write-Host "Scaning files via size $threshold bit..." -ForegroundColor Cyan

# 获取所有文件（排除目录）
$allFiles = Get-ChildItem -Path $source -Recurse | Where-Object { !$_.PSIsContainer }

# 分成两组：大文件和小文件
$largeFiles = $allFiles | Where-Object { $_.Length -ge $threshold }
$smallFiles = $allFiles | Where-Object { $_.Length -lt $threshold }

$totalLarge = ($largeFiles | Measure-Object).Count
$totalSmall = ($smallFiles | Measure-Object).Count

Write-Host "Scaning done" -ForegroundColor White
Write-Host "  - small files (<100MB): $totalSmall  (Using MT:4)" -ForegroundColor Green
Write-Host "  - Large files (>=100MB): $totalLarge (Using /J copy via IO)" -ForegroundColor Yellow
Write-Host "--------------------------------------------"

# --- 2. 处理小文件 (分块多线程处理以提高效率) ---
if ($totalSmall -gt 0) {
    Write-Host "Using MT:4 copying small files..." -ForegroundColor Green
    # 注意：小文件我们不需要循环执行，直接交给 robocopy 过滤大小并开启多线程更高效
    robocopy $source $dest /E /MT:4 /MAX:($threshold - 1) /W:1 /R:1 /NP /NJH /NJS /NDL /NFL
}

# --- 3. 处理大文件 (循环执行并显示进度) ---
if ($totalLarge -gt 0) {
    Write-Host "`nUsing /J copying large files..." -ForegroundColor Yellow
    $currentCount = 0
    
    foreach ($file in $largeFiles) {
        $currentCount++
        $relative = $file.FullName.Replace($source, "")
        $targetPath = Join-Path $dest $relative
        $targetDir = Split-Path $targetPath
        
        # 显示进度条
        $percentVal = [Math]::Min(100, [Math]::Round(($currentCount / $totalLarge) * 100, 1))
        Write-Progress -Activity "Syncing Large Files" `
                       -Status "File $currentCount of $totalLarge" `
                       -PercentComplete $percentVal
        
        # 实时显示当前文件名
        Write-Host "`rCopying: [ $currentCount / $totalLarge ] - $($file.Name)" -NoNewline
        
        # 执行大文件专用 Robocopy 逻辑
        robocopy $file.DirectoryName $targetDir $file.Name /MT:1 /J /W:1 /R:1 /NP /NJH /NJS /NDL /NFL > $null
    }
}

Write-Host "`nCopying done" -ForegroundColor Cyan