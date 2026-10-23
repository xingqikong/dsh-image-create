# apply-fix.ps1 —— 把 dsh-image-create 的修复重新打进任意一份 sd-inject.ps1
# 用途：插件升级/重装会把 sd-inject.ps1 换回上游版本，这时用它重打一遍。
# 用法：
#   .\tools\apply-fix.ps1 -Path "<插件包>\sd-inject.ps1"
#   .\tools\apply-fix.ps1 -Path ".\sd-inject.ps1"
# 说明：逐条校验锚点（每条命中次数必须为 1），任一不匹配即报错退出，不会写出半成品；
#       输出为 UTF-8 with BOM（PowerShell 5.1 读中文必需）。
# 重新打补丁：把 sd-inject.ps1（插件包里的模板）改成修复版
param([string]$Path)
$ErrorActionPreference = 'Stop'
$text = [System.Text.Encoding]::UTF8.GetString([System.IO.File]::ReadAllBytes($Path)).TrimStart([char]0xFEFF)
$text = $text -replace "`r`n", "`n"   # 统一成 LF 再匹配，避免 CRLF/LF 混用导致锚点不命中
$fail = 0

function Rep([string]$old, [string]$new, [string]$tag) {
    $script:text = $script:text
    $n = ([regex]::Matches($script:text, [regex]::Escape($old))).Count
    if ($n -ne 1) { Write-Host "[FAIL] $tag : 命中 $n 次（应为 1）" -ForegroundColor Red; $script:fail++; return }
    $script:text = $script:text.Replace($old, $new)
    Write-Host "[OK] $tag" -ForegroundColor Green
}

# ---------- 1) 表单：尺寸 / 参数 / 底图栏 / 按钮 ----------
Rep '$form.ClientSize = New-Object System.Drawing.Size(350, 606)' '$form.ClientSize = New-Object System.Drawing.Size(350, 662)' '1 表单尺寸'

Rep @'
        [string[]]$LoraList,
        [string[]]$CheckpointList
    )
'@ @'
        [string[]]$LoraList,
        [string[]]$CheckpointList,
        [string]$InitImage = "",      # 预填的底图路径（-InitImage 传进来时就填好）
        [string]$BrowseDir = ""       # 「浏览…」的默认目录（一般指向 SD-Picture）
    )
'@ '2 表单参数 InitImage/BrowseDir'

Rep "    foreach (`$v in @('0（文生图·不用底图）', '0.3', '0.4', '0.5', '0.6', '0.7', '0.8', '0.9')) { `$null = `$cboDenoise.Items.Add(`$v) }" "    foreach (`$v in @('0（文生图·不用底图）', '0.1', '0.2', '0.3', '0.35', '0.4', '0.45', '0.5', '0.55', '0.6', '0.65', '0.7', '0.75', '0.8', '0.85', '0.9', '0.95')) { `$null = `$cboDenoise.Items.Add(`$v) }" '3 Denoising 档位'

$initUI = @'


    # 9) 底图（图生图专用：选你准备好的那张图；留空 = 老流程「用素体基底/现场补一张」）
    # 选了底图后：自动按这张图的宽高比匹配「比例」、按短边匹配「画质」，
    # 并把 Denoising 从 0 抬到 0.55——否则用户很容易忘了改 Denoising，又变成文生图。
    $lbInit = New-Object System.Windows.Forms.Label
    $lbInit.Text = '底图：'
    $lbInit.SetBounds(20, (240 + 8 * 40), 90, 22)
    $form.Controls.Add($lbInit)

    $txtInit = New-Object System.Windows.Forms.TextBox
    $txtInit.Text = $InitImage
    $txtInit.SetBounds(120, (240 + 8 * 40), 120, 24)
    $form.Controls.Add($txtInit)

    $btnInit = New-Object System.Windows.Forms.Button
    $btnInit.Text = '浏览…'
    $btnInit.SetBounds(246, (240 + 8 * 40), 64, 24)
    $form.Controls.Add($btnInit)

    $lbInitHint = New-Object System.Windows.Forms.Label
    $lbInitHint.Text = '（留空 = 自动用素体底图；选了就按你的图图生图）'
    $lbInitHint.Font = New-Object System.Drawing.Font('Microsoft YaHei', 7.5)
    $lbInitHint.ForeColor = [System.Drawing.Color]::Gray
    $lbInitHint.SetBounds(120, (240 + 8 * 40 + 26), 230, 18)
    $form.Controls.Add($lbInitHint)

    # 底图 → 自动匹配比例 / 画质（按你那张图的形状与分辨率出图，不拉伸变形）
    $applyInitInfo = {
        $p = ([string]$txtInit.Text).Trim().Trim('"').Trim("'")
        if (-not $p -or -not (Test-Path -LiteralPath $p)) { return }
        try {
            $img = [System.Drawing.Image]::FromFile($p)
            $iw = $img.Width; $ih = $img.Height
            $img.Dispose()
        } catch { return }
        $ar = [double]$iw / [double]$ih
        $bestIdx = 0; $bestDiff = 99.0
        for ($i = 0; $i -lt $cboRatio.Items.Count; $i++) {
            if (([string]$cboRatio.Items[$i]) -match '^(\d+):(\d+)$') {
                $diff = [math]::Abs($ar - ([double]$Matches[1] / [double]$Matches[2]))
                if ($diff -lt $bestDiff) { $bestDiff = $diff; $bestIdx = $i }
            }
        }
        $cboRatio.SelectedIndex = $bestIdx
        $short = [math]::Min($iw, $ih)
        $qBest = 0; $qDiff = 99999
        for ($i = 0; $i -lt $cboQuality.Items.Count; $i++) {
            if (([string]$cboQuality.Items[$i]) -match '^(\d+)p') {
                $diff = [math]::Abs($short - [int]$Matches[1])
                if ($diff -lt $qDiff) { $qDiff = $diff; $qBest = $i }
            }
        }
        $cboQuality.SelectedIndex = $qBest
    }

    $btnInit.Add_Click({
        $ofd = New-Object System.Windows.Forms.OpenFileDialog
        $ofd.Title = '选择要作为图生图底图的图片'
        $ofd.Filter = '图片 (*.png;*.jpg;*.jpeg;*.webp;*.bmp)|*.png;*.jpg;*.jpeg;*.webp;*.bmp|所有文件 (*.*)|*.*'
        if ($BrowseDir -and (Test-Path -LiteralPath $BrowseDir)) { $ofd.InitialDirectory = $BrowseDir }
        if ($ofd.ShowDialog() -eq 'OK') {
            $txtInit.Text = $ofd.FileName
            & $applyInitInfo
            if (-not $cboDenoise.Text -or $cboDenoise.Text -eq '0' -or $cboDenoise.Text -match '^0\s*（') { $cboDenoise.Text = '0.55' }
        }
    })

    # -InitImage 传进来时表单已经预填了路径：顺手把比例/画质调成跟这张图一致
    if ($InitImage) { & $applyInitInfo }
'@

Rep @'
    $lbNameHint.SetBounds(120, (240 + 7 * 40 + 26), 220, 18)
    $form.Controls.Add($lbNameHint)

    $btnOk = New-Object System.Windows.Forms.Button
    $btnOk.Text = '确定出图'
    $btnOk.SetBounds(110, 564, 100, 30)
    $form.AcceptButton = $btnOk
    $form.Controls.Add($btnOk)

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = '取消'
    $btnCancel.SetBounds(220, 564, 100, 30)
    $form.Controls.Add($btnCancel)
'@ ("    `$lbNameHint.SetBounds(120, (240 + 7 * 40 + 26), 220, 18)`r`n    `$form.Controls.Add(`$lbNameHint)`r`n" + $initUI + @'

    $btnOk = New-Object System.Windows.Forms.Button
    $btnOk.Text = '确定出图'
    $btnOk.SetBounds(110, 608, 100, 30)
    $form.AcceptButton = $btnOk
    $form.Controls.Add($btnOk)

    $btnCancel = New-Object System.Windows.Forms.Button
    $btnCancel.Text = '取消'
    $btnCancel.SetBounds(220, 608, 100, 30)
    $form.Controls.Add($btnCancel)
'@) '4 底图栏 + 按钮下移'

Rep @'
        Model   = [string]$cboModel.SelectedItem
        Name    = $txtName.Text.Trim()
    }
}
'@ @'
        Model   = [string]$cboModel.SelectedItem
        Name    = $txtName.Text.Trim()
        InitImage = ([string]$txtInit.Text).Trim().Trim('"').Trim("'")
    }
}
'@ '5 表单返回 InitImage'

# ---------- 2) 解析加固 ----------
Rep @'
    # 解析：非法输入回落默认（迭代次数回落默认轮数、Denoising 回落 0 = 文生图）
    $rounds = $DefaultRounds
    $null = [int]::TryParse($cboRounds.Text.Trim(), [ref]$rounds)
    if ($rounds -lt 1) { $rounds = 1 } elseif ($rounds -gt 32) { $rounds = 32 }
    # Denoising **恒定解析**（不再按 HasBaseImage 强行归零——表单先弹，那一刻必然还没有素体成品）：
    # 取文本框开头的数字（兼容「0（文生图·不用底图）」这类带说明的条目），0 = 文生图，>0 = 图生图重绘幅度；
    # 空值/非法 → 0（等于现状行为）。上限 0.95，防止填 1 直接把底图信息全洗掉。
    $den = 0.0
    $denMatch = [regex]::Match(($cboDenoise.Text -replace ',', '.').Trim(), '^[0-9]*\.?[0-9]+')
    if ($denMatch.Success) { $null = [double]::TryParse($denMatch.Value, [ref]$den) }
    if ($den -lt 0) { $den = 0 } elseif ($den -gt 0.95) { $den = 0.95 }
'@ @'
    # 解析：非法输入回落默认（迭代次数回落默认轮数、Denoising 回落 0 = 文生图）
    # 迭代次数：取开头数字（「8」「8 轮」都认），限制 1-32
    $rounds = $DefaultRounds
    $roundsMatch = [regex]::Match(([string]$cboRounds.Text).Trim(), '^\d+')
    if ($roundsMatch.Success) { $null = [int]::TryParse($roundsMatch.Value, [ref]$rounds) }
    if ($rounds -lt 1) { $rounds = 1 } elseif ($rounds -gt 32) { $rounds = 32 }
    # Denoising **恒定解析**（不再按 HasBaseImage 强行归零——表单先弹，那一刻必然还没有素体成品）：
    # 取文本框开头的数字（兼容「0（文生图·不用底图）」「0.5」这类条目），全角数字/中文逗号也归一；
    # 0 = 文生图，>0 = 图生图重绘幅度；非数字就给一行警告再按 0 处理（不再静默）。上限 0.95。
    $denText = [string]$cboDenoise.Text
    $denNorm = $denText.Replace('，', ',').Replace('．', '.').Replace(',', '.')
    for ($d = 0; $d -lt 10; $d++) { $denNorm = $denNorm.Replace([char](0xFF10 + $d), [char](0x30 + $d)) }
    $den = 0.0
    $denMatch = [regex]::Match($denNorm.Trim(), '^\d*\.?\d+')
    if ($denMatch.Success) {
        $null = [double]::TryParse($denMatch.Value, [ref]$den)
    } elseif ($denNorm.Trim()) {
        Write-Host "Denoising 填的「$denText」不是数字，本次按 0（文生图）处理" -ForegroundColor Yellow
    }
    if ($den -lt 0) { $den = 0 } elseif ($den -gt 0.95) { $den = 0.95 }
'@ '6 解析加固'

# ---------- 3) 主流程：底图 / 回显 / 跳过素体迭代 ----------
Rep @'
$P = Show-ParamForm -DefaultRounds $paramFormRounds -HasBaseImage $hasBaseImg -Positive $formPositive -Negative $formNegative -LoraList $sdLoras -CheckpointList $sdCheckpoints
# 表单里的提示词是最终值（基底 + 用户在表单里的修改/追加）
$positive = $P.Pos
$negative = $P.Neg
'@ @'
$P = Show-ParamForm -DefaultRounds $paramFormRounds -HasBaseImage $hasBaseImg -Positive $formPositive -Negative $formNegative -LoraList $sdLoras -CheckpointList $sdCheckpoints -InitImage $InitImage -BrowseDir $OutDir
# 表单里的提示词是最终值（基底 + 用户在表单里的修改/追加）
$positive = $P.Pos
$negative = $P.Neg

# 用户自己准备的底图（表单「底图：」或 -InitImage）：有它就直接拿它做图生图底图，跳过素体迭代。
$userInit = [string]$P.InitImage
if ($userInit -and -not (Test-Path -LiteralPath $userInit)) {
    Write-Host "底图不存在：$userInit —— 本次忽略，仍按自动底图（素体基底/现场补一张）走" -ForegroundColor Yellow
    $userInit = ''
}
if ($userInit) {
    # 有底图但 Denoising=0 时，脚本会走文生图、底图等于没用；自动抬到 0.55 并说明（用户最容易漏这一步）
    if ($P.Denoise -le 0) {
        $P.Denoise = 0.55
        Write-Host "已选底图但 Denoising 是 0（文生图）→ 自动按 Denoising 0.55 走图生图" -ForegroundColor Yellow
    }
    Write-Host "本次用你准备的底图：$userInit" -ForegroundColor Cyan
}
'@ '7 底图识别 + 自动抬 Denoising'

Rep @'
Write-Host ""
Write-Host "开始绘制" -ForegroundColor Cyan
'@ @'
Write-Host ""
Write-Host "开始绘制" -ForegroundColor Cyan
# 立即回显「表单实际取到的值」：Denoising 这类参数若没生效，这里第一眼就能看出来。
$echoDen = if ($P.Denoise -gt 0) { "Denoising $($P.Denoise)（图生图）" } else { "Denoising 0（文生图）" }
$echoLora = if ($P.Lora -and $P.Lora -ne '（不用 LoRA）') { $P.Lora } else { '不用' }
$echoModel = if ($P.Model -and $P.Model -ne '（当前模型）') { $P.Model } else { '当前模型' }
$echoName = if ($P.Name) { $P.Name } else { '(自动命名)' }
$echoInit = if ($userInit) { "你的底图" } else { '自动（素体基底）' }
Write-Host "表单已确认：迭代 $($P.Rounds) 次 | $echoDen | 比例 $($P.Ratio) | 画风 $($P.Style) | 画质 $($P.Quality) | LoRA $echoLora | 模型 $echoModel | 底图 $echoInit | 命名 $echoName" -ForegroundColor Cyan
'@ '8+9 回显实际参数'

Rep 'if ($positive -and ($positive -notmatch $framingWords)) {' 'if (-not $userInit -and $positive -and ($positive -notmatch $framingWords)) {' '10 有底图不塞 full body'

Rep @'
$baseWin = $null
if (-not $NoIterate) {
    $baseWin = Invoke-BaseIterate
    if ($baseWin) {
        Write-Host "素体迭代完成：$($baseWin.Path)（seed=$($baseWin.Seed)，脸/手 $($baseWin.Score)/100）" -ForegroundColor Green
    }
}
'@ @'
$baseWin = $null
if ($userInit) {
    $baseWin = @{ Path = $userInit; Seed = -1; Score = -1 }
    Write-Host "已用你的底图 → 跳过素体自检迭代（直接按这张图做图生图）" -ForegroundColor DarkGray
} elseif (-not $NoIterate) {
    $baseWin = Invoke-BaseIterate
    if ($baseWin) {
        Write-Host "素体迭代完成：$($baseWin.Path)（seed=$($baseWin.Seed)，脸/手 $($baseWin.Score)/100）" -ForegroundColor Green
    }
}
'@ '11 有底图跳过素体迭代'

Rep @'
if ($baseWin -and (Test-Path -LiteralPath $baseWin.Path)) { $hasBaseImg = $true }

# 脸部细节词：自动追加进正向（去重——用户已手写过的词不重复加）
'@ @'
if ($baseWin -and (Test-Path -LiteralPath $baseWin.Path)) { $hasBaseImg = $true }

# ---- 0c) Denoising>0 的底图兜底（修「选了 Denoising 又回到 0」）----
# 根因：Denoising 只对「图生图」生效，而图生图的底图原先**只能**是素体自检迭代的 winning 图；
#   素体迭代又依赖本地视觉模型。没装/没起模型（或传了 -NoIterate）时迭代返回空，
#   表单里选的 Denoising 就被静默按 0（文生图）跑掉。
# 修法：Denoising>0 而手里没有底图时，现场补一张素体底图（不质检、只一张），保证一定走图生图。
if ($P.Denoise -gt 0 -and -not ($baseWin -and (Test-Path -LiteralPath $baseWin.Path))) {
    Write-Host "Denoising $($P.Denoise) 需要底图，但素体自检迭代没有产出（视觉模型不可用，或传了 -NoIterate）→ 现场补一张素体底图" -ForegroundColor Yellow
    $baseWin = Invoke-BaseOnce
    if ($baseWin -and (Test-Path -LiteralPath $baseWin.Path)) {
        $hasBaseImg = $true
        Write-Host "底图已就绪：$($baseWin.Path)（seed=$($baseWin.Seed)）" -ForegroundColor Green
    } else {
        Write-Host "补底图失败：本次只能退回文生图（Denoising 不生效）" -ForegroundColor Red
    }
}

# 脸部细节词：自动追加进正向（去重——用户已手写过的词不重复加）
'@ '12 0c 补底图兜底'

# ---------- 4) 视觉模型：自动拉起 / 补底图函数 / 预热不卡死 ----------
Rep @'
    # 铁律：本函数不修改 $positive / $negative 的任何内容——不加词、不加替换词、不加安全词。
    if (-not (Test-VlmApi)) {
        # 视觉质检不可用：不做无意义的迭代，保持老行为直接出一张
        Write-Host "本地视觉模型不可用（$QwenBase），跳过素体自检迭代（可用 -NoIterate 显式关闭）" -ForegroundColor Yellow
        return $null
    }
'@ @'
    # 铁律：本函数不修改 $positive / $negative 的任何内容——不加词、不加替换词、不加安全词。
    # 质检服务没起就先试着拉起来（装了 Ollama 但托盘没自启的情况下，这一步能让质检照常工作）
    $null = Start-OllamaIfNeeded
    if (-not (Test-VlmApi)) {
        # 视觉质检不可用：不做无意义的迭代，保持老行为直接出一张
        Write-Host "本地视觉模型不可用（$QwenBase），跳过素体自检迭代（可用 -NoIterate 显式关闭）" -ForegroundColor Yellow
        Write-Host "  想让脸/手质检生效：跑本目录的 .\install-ollama.ps1（自动装 Ollama + 拉 qwen3-vl:4b）" -ForegroundColor Yellow
        return $null
    }
'@ '13 素体迭代前自动拉起 Ollama'

Rep @'
    if (-not $bestPath) { return $null }
    return @{ Path = $bestPath; Seed = $bestSeed; Score = $bestScore; RoundsUsed = $roundsUsed }
}
'@ @'
    if (-not $bestPath) { return $null }
    return @{ Path = $bestPath; Seed = $bestSeed; Score = $bestScore; RoundsUsed = $roundsUsed }
}

function Invoke-BaseOnce {
    # 「补底图」：只出一张素体基底图（不质检、不迭代、不换 seed）。
    # 存在意义：Denoising>0 的图生图必须有底图，而素体自检迭代依赖本地视觉模型。
    # 视觉模型不可用（或传了 -NoIterate）时迭代返回空 → 以前就把 Denoising 静默按 0 跑掉。
    # 返回 @{ Path; Seed; Score = -1 }；失败返回 $null。
    $genArgs = @(
        "-ExecutionPolicy", "Bypass", "-File", "`"$SdDirect`"",
        "-Prompt", "`"$BasePrompt`"",
        "-Negative", "`"$BaseNegative`"",
        "-Width", "$Width", "-Height", "$Height",
        "-Steps", "$Steps", "-Cfg", "$Cfg",
        "-Sampler", "`"$Sampler`"",
        "-Seed", "-1",
        "-OutDir", "`"$script:IterTempDir`"",
        "-Name", "`"$Name`""
    )
    if ($SdDir) { $genArgs += @("-SdDir", "`"$SdDir`"") }
    $genArgs += "-NoOpen"
    Write-Host "补底图：用素体基底出 1 张（只出图、不质检）..." -ForegroundColor Cyan
    $genOut = & powershell @genArgs 2>&1
    $genOut | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0) {
        Write-Host "补底图失败（exit $LASTEXITCODE）" -ForegroundColor Red
        return $null
    }
    $genSeed = -1
    $seedLine = @($genOut | Where-Object { $_ -match '^SEEDVALUE:\s*(\d+)' } | Select-Object -First 1)
    if ($seedLine -and $seedLine -match '^SEEDVALUE:\s*(\d+)') { $genSeed = [long]$Matches[1] }
    $cand = Get-ChildItem -LiteralPath $script:IterTempDir -Filter "$Name`_*.png" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $cand) {
        Write-Host "补底图失败：找不到产物（$script:IterTempDir\$Name`_*.png）" -ForegroundColor Red
        return $null
    }
    return @{ Path = $cand.FullName; Seed = $genSeed; Score = -1 }
}
'@ '14 新增 Invoke-BaseOnce'

Rep @'
function Find-Ollama {
    $cmd = Get-Command ollama -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    foreach ($c in @("$env:LOCALAPPDATA\Programs\Ollama\ollama.exe", "D:\ollama\ollama.exe", "C:\ollama\ollama.exe", "$env:ProgramFiles\Ollama\ollama.exe", "${env:ProgramFiles(x86)}\Ollama\ollama.exe")) {
        if ($c -and (Test-Path -LiteralPath $c)) { return $c }
    }
    return ''
}
'@ @'
function Find-Ollama {
    $cmd = Get-Command ollama -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }
    foreach ($c in @("$env:LOCALAPPDATA\Programs\Ollama\ollama.exe", "D:\ollama\ollama.exe", "C:\ollama\ollama.exe", "$env:ProgramFiles\Ollama\ollama.exe", "${env:ProgramFiles(x86)}\Ollama\ollama.exe")) {
        if ($c -and (Test-Path -LiteralPath $c)) { return $c }
    }
    return ''
}

function Start-OllamaIfNeeded {
    # 视觉质检（Ollama）装了但服务没起，是最常见的「质检突然不工作」原因（重启后托盘没自启 / 手动关过）。
    # 这里自动把 serve 拉起来并等它就绪；没装则返回 $false，主流程照常跳过质检。
    if (Test-VlmApi) { return $true }
    $exe = Find-Ollama
    if (-not $exe) { return $false }
    Write-Host "视觉质检服务没在跑，尝试启动 Ollama：$exe" -ForegroundColor Yellow
    try { Start-Process -FilePath $exe -ArgumentList 'serve' -WindowStyle Hidden | Out-Null } catch { return $false }
    for ($i = 0; $i -lt 25; $i++) {
        Start-Sleep -Milliseconds 800
        if (Test-VlmApi) { return $true }
    }
    return $false
}
'@ '15 新增 Start-OllamaIfNeeded'

Rep @'
        $preheatOut = & powershell @preheatArgs 2>&1
        $preheatOut | ForEach-Object { Write-Host $_ }
'@ @'
        # 直接跑、**不捕获输出**（不要 `= & powershell ... 2>&1`）：sd-direct 拉起 SD 的子进程会继承
        # 本进程的 stdout 管道句柄，SD 一直活着 → 管道永不关闭 → 这里死等，表单永远不弹。
        & powershell @preheatArgs
'@ '16 预热不捕获输出（修卡死）'

Rep '    [string]$VlmModel = "qwen3-vl:8b",                 # 脸部质检用的本地视觉模型（留空 "" = 自动挑本机 vl/vision 模型）' '    [string]$VlmModel = "qwen3-vl:4b",                 # 脸部质检用的本地视觉模型（4b：8G 显存与 SD 共存更稳；显存大可传 qwen3-vl:8b；留空 = 自动挑本机 vl/vision 模型）' '17 默认质检模型 4b'

Rep '    [string]$VlmModel = "qwen3-vl:4b",                 # 脸部质检用的本地视觉模型（4b：8G 显存与 SD 共存更稳；显存大可传 qwen3-vl:8b；留空 = 自动挑本机 vl/vision 模型）
    [int]$SdPort = 7860,                               # SD API 端口（拉取 LoRA 列表用）' '    [string]$VlmModel = "qwen3-vl:4b",                 # 脸部质检用的本地视觉模型（4b：8G 显存与 SD 共存更稳；显存大可传 qwen3-vl:8b；留空 = 自动挑本机 vl/vision 模型）
    [string]$InitImage = "",                           # 自定义底图（你的图 → 图生图）；留空 = 用素体基底/现场补一张
    [int]$SdPort = 7860,                               # SD API 端口（拉取 LoRA 列表用）' '18 顶层 -InitImage 参数'

Rep 'Write-Host "本机没有视觉模型（vl/vision），跳过素体自检迭代；想用请先：ollama pull qwen3-vl:8b" -ForegroundColor Yellow' 'Write-Host "本机没有视觉模型（vl/vision），跳过素体自检迭代；想用请先：ollama pull $VlmModel（或跑本目录的 install-ollama.ps1）" -ForegroundColor Yellow' '19 提示信息用变量'

Rep @'
    if ($baseWin -and (Test-Path -LiteralPath $baseWin.Path)) {
        $finalInit = $baseWin.Path
        $finalDenoise = $P.Denoise
        Write-Host "最终出图走图生图：底图 = 素体成品（seed=$($baseWin.Seed)），denoising = $finalDenoise" -ForegroundColor Cyan
    } else {
        Write-Host "表单填了 Denoising $($P.Denoise)，但素体迭代没有可用成品（-NoIterate 或迭代失败）→ 本次仍走文生图" -ForegroundColor Yellow
    }
'@ @'
    if ($baseWin -and (Test-Path -LiteralPath $baseWin.Path)) {
        $finalInit = $baseWin.Path
        $finalDenoise = $P.Denoise
        $initFrom = if ($userInit) { '你准备的图' } else { "素体基底（seed=$($baseWin.Seed)）" }
        Write-Host "最终出图走图生图：底图 = $initFrom，denoising = $finalDenoise" -ForegroundColor Cyan
    } else {
        Write-Host "表单填了 Denoising $($P.Denoise)，但补底图也失败 → 本次只能走文生图" -ForegroundColor Yellow
    }
'@ '20 最终分支文案'

# ---------- 5) 多选模式（出满 N 张后弹列表挑）----------
Rep @'
    $lbInitHint.SetBounds(120, (240 + 8 * 40 + 26), 230, 18)
    $form.Controls.Add($lbInitHint)
'@ @'
    $lbInitHint.SetBounds(120, (240 + 8 * 40 + 26), 230, 18)
    $form.Controls.Add($lbInitHint)

    # 多选模式：出满「迭代次数」张后弹列表让你勾选保留（默认关；质检能用时默认只留最高分那张）
    $chkPickAll = New-Object System.Windows.Forms.CheckBox
    $chkPickAll.Text = '多选：出满 N 张后弹列表让我挑'
    $chkPickAll.SetBounds(20, 606, 320, 22)
    $chkPickAll.Checked = $PickAll
    $form.Controls.Add($chkPickAll)
'@ '21 多选勾选框'

Rep '$form.ClientSize = New-Object System.Drawing.Size(350, 662)' '$form.ClientSize = New-Object System.Drawing.Size(350, 690)' '22 表单再加高'
Rep '    $btnOk.SetBounds(110, 608, 100, 30)' '    $btnOk.SetBounds(110, 634, 100, 30)' '23 按钮下移 OK'
Rep '    $btnCancel.SetBounds(220, 608, 100, 30)' '    $btnCancel.SetBounds(220, 634, 100, 30)' '24 按钮下移 Cancel'

Rep @'
        [string]$BrowseDir = ""       # 「浏览…」的默认目录（一般指向 SD-Picture）
    )
'@ @'
        [string]$BrowseDir = "",      # 「浏览…」的默认目录（一般指向 SD-Picture）
        [bool]$PickAll = $false       # 多选模式默认值（-PickAll 传进来时勾上）
    )
'@ '25 表单参数 PickAll'

Rep @'
        InitImage = ([string]$txtInit.Text).Trim().Trim('"').Trim("'")
    }
}
'@ @'
        InitImage = ([string]$txtInit.Text).Trim().Trim('"').Trim("'")
        PickAll = [bool]$chkPickAll.Checked
    }
}
'@ '26 表单返回 PickAll'

Rep '$P = Show-ParamForm -DefaultRounds $paramFormRounds -HasBaseImage $hasBaseImg -Positive $formPositive -Negative $formNegative -LoraList $sdLoras -CheckpointList $sdCheckpoints -InitImage $InitImage -BrowseDir $OutDir' '$P = Show-ParamForm -DefaultRounds $paramFormRounds -HasBaseImage $hasBaseImg -Positive $formPositive -Negative $formNegative -LoraList $sdLoras -CheckpointList $sdCheckpoints -InitImage $InitImage -BrowseDir $OutDir -PickAll ([bool]$PickAll)' '27 表单传 PickAll'

Rep @'
    [string]$InitImage = "",                           # 自定义底图（你的图 → 图生图）；留空 = 用素体基底/现场补一张
    [int]$SdPort = 7860,                               # SD API 端口（拉取 LoRA 列表用）
'@ @'
    [string]$InitImage = "",                           # 自定义底图（你的图 → 图生图）；留空 = 用素体基底/现场补一张
    [switch]$PickAll,                                  # 多选模式：出满迭代次数后弹列表让你勾选保留（默认只留最高分那张）
    [int]$SdPort = 7860,                               # SD API 端口（拉取 LoRA 列表用）
'@ '28 顶层 -PickAll'

Rep @'
        [string]$Checkpoint = ""
    )
'@ @'
        [string]$Checkpoint = "",
        [switch]$ForceAll = $false
    )
'@ '29 FinalIterate 参数'

Rep @'
        if ($score -ge 75) { break }
    }
    if ($allPaths.Count -eq 0) { return $null }
'@ @'
        if ($score -ge 75 -and -not $ForceAll) { break }
    }
    if ($allPaths.Count -eq 0) { return $null }
'@ '30 多选时不提前停'

Rep '$finalWin = Invoke-FinalIterate -InitImage $finalInit -Denoising $finalDenoise -Rounds $P.Rounds -W $size.W -H $size.H -Checkpoint $formCheckpoint' '$finalWin = Invoke-FinalIterate -InitImage $finalInit -Denoising $finalDenoise -Rounds $P.Rounds -W $size.W -H $size.H -Checkpoint $formCheckpoint -ForceAll:([bool]$P.PickAll)' '31 传 ForceAll'

Rep '    if ($finalWin.VlmDown) {' '    if ($finalWin.VlmDown -or $P.PickAll) {' '32 多选走列表分支'

Rep '        Write-Host "质检模型未就绪，已生成 $($finalWin.Paths.Count) 张候选图：" -ForegroundColor Green' '        $why = if ($P.PickAll) { ''多选模式'' } else { ''质检模型未就绪'' }
        Write-Host "$why，已生成 $($finalWin.Paths.Count) 张候选图：" -ForegroundColor Green' '33 列表分支文案'

# ---------- 收尾：统一 CRLF + 写回 ----------
$text = $text.Replace("`r`n", "`n").Replace("`n", "`r`n")
[System.IO.File]::WriteAllText($Path, $text, (New-Object System.Text.UTF8Encoding($true)))
Write-Host ""
if ($fail -eq 0) { Write-Host "全部补丁已应用：$Path" -ForegroundColor Green } else { Write-Host "$fail 处失败" -ForegroundColor Red; exit 1 }
