# install-ollama.ps1 —— 一键装好 sd-inject 需要的本地视觉质检（Ollama + 视觉模型）
# 干什么：
#   1) 没装 Ollama 就下载官方安装包（GitHub 慢会自动换镜像）并静默安装；
#   2) 拉起 Ollama 服务（127.0.0.1:11434），没起来就后台 ollama serve；
#   3) 拉视觉模型（默认 qwen3-vl:4b：8G 显存和 SD 共存更稳；显存大可 -Model qwen3-vl:8b）；
#   4) 验证 /v1/models 能列出这个模型，并给出 sd-inject 的用法。
#
# 用法（在 sd-inject.ps1 同目录执行）：
#   .\install-ollama.ps1                       # 装 4b（推荐 8G 显存）
#   .\install-ollama.ps1 -Model qwen3-vl:8b    # 装 8b（12G+ 显存更合适）
#   .\install-ollama.ps1 -SkipModel            # 只装 Ollama，不拉模型
#   重复执行是安全的：已装的会跳过下载/安装，已拉的会跳过拉取。

param(
    [string]$Model = "qwen3-vl:4b",
    [switch]$SkipModel,
    [string]$InstallerUrl = "https://github.com/ollama/ollama/releases/latest/download/OllamaSetup.exe"
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

function Say([string]$msg, [string]$color = 'Gray') { Write-Host $msg -ForegroundColor $color }

function Find-OllamaExe {
    $cmd = Get-Command ollama -ErrorAction SilentlyContinue
    if ($cmd -and (Test-Path -LiteralPath $cmd.Source)) { return $cmd.Source }
    foreach ($c in @(
            "$env:LOCALAPPDATA\Programs\Ollama\ollama.exe",
            "$env:ProgramFiles\Ollama\ollama.exe",
            "${env:ProgramFiles(x86)}\Ollama\ollama.exe",
            "C:\ollama\ollama.exe",
            "D:\ollama\ollama.exe")) {
        if ($c -and (Test-Path -LiteralPath $c)) { return $c }
    }
    return ''
}

function Test-OllamaApi {
    try {
        $null = Invoke-RestMethod -Uri 'http://127.0.0.1:11434/api/tags' -Method Get -TimeoutSec 3
        return $true
    } catch { return $false }
}

function Get-Installer([string]$url, [string]$dst) {
    # 直连 GitHub → 失败/太慢时依次换镜像；curl.exe 有就用它（带进度），没有就 Invoke-WebRequest
    $targets = @(
        $url,
        "https://gh-proxy.com/$url",
        "https://ghproxy.net/$url",
        "https://ghfast.top/$url"
    )
    foreach ($t in $targets) {
        Say "下载：$t" Cyan
        Remove-Item -LiteralPath $dst -Force -ErrorAction SilentlyContinue
        try {
            if (Get-Command curl.exe -ErrorAction SilentlyContinue) {
                & curl.exe -L --retry 3 --retry-delay 2 --max-time 1800 -o $dst $t
                if ($LASTEXITCODE -ne 0) { throw "curl 退出码 $LASTEXITCODE" }
            } else {
                Invoke-WebRequest -Uri $t -OutFile $dst -UseBasicParsing -TimeoutSec 1800
            }
            if ((Test-Path -LiteralPath $dst) -and ((Get-Item -LiteralPath $dst).Length -gt 50MB)) { return $true }
            Say "  这份太小/不完整，换下一个源" Yellow
        } catch {
            Say "  失败：$($_.Exception.Message)" Yellow
        }
    }
    return $false
}

# ---- 1) 找/装 Ollama ----
$ollama = Find-OllamaExe
if ($ollama) {
    Say "已安装 Ollama：$ollama" Green
} else {
    Say "未检测到 Ollama，开始下载安装包..." Cyan
    $setup = Join-Path ([System.IO.Path]::GetTempPath()) 'OllamaSetup.exe'
    if (-not (Get-Installer -url $InstallerUrl -dst $setup)) {
        Say "安装包下载失败（GitHub 与镜像都不通）。可以手动装：https://ollama.com/download/windows，装完再跑一次本脚本。" Red
        exit 1
    }
    Say "安装包已就绪：$setup（$([math]::Round((Get-Item -LiteralPath $setup).Length / 1MB, 1)) MB）" Green
    Say "静默安装中（约 1-2 分钟）..." Cyan
    $p = Start-Process -FilePath $setup -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/SP-' -PassThru -Wait
    if ($p.ExitCode -ne 0) { Say "安装程序退出码 $($p.ExitCode)（不一定失败，先看看是否已装上）" Yellow }
    $ollama = Find-OllamaExe
    if (-not $ollama) {
        Say "安装后仍找不到 ollama.exe。请手动打开一次 Ollama，再跑本脚本。" Red
        exit 1
    }
    Say "安装完成：$ollama" Green
}

# ---- 2) 拉起服务 ----
if (Test-OllamaApi) {
    Say "Ollama 服务已在运行（127.0.0.1:11434）" Green
} else {
    Say "Ollama 服务没起来，后台启动 ollama serve..." Cyan
    Start-Process -FilePath $ollama -ArgumentList 'serve' -WindowStyle Hidden | Out-Null
    $ok = $false
    for ($i = 0; $i -lt 30; $i++) {
        Start-Sleep -Seconds 1
        if (Test-OllamaApi) { $ok = $true; break }
    }
    if (-not $ok) { Say "服务 30 秒内没就绪。可手动开一次 Ollama 应用后再跑本脚本。" Red; exit 1 }
    Say "服务已就绪" Green
}

if ($SkipModel) { Say "已按要求跳过模型拉取（-SkipModel）" Yellow; exit 0 }

# ---- 3) 拉视觉模型 ----
Say "检查模型 $Model ..." Cyan
$have = @()
try { $have = @((Invoke-RestMethod -Uri 'http://127.0.0.1:11434/api/tags' -TimeoutSec 10).models | ForEach-Object { [string]$_.name }) } catch { }
if ($have -contains $Model -or @($have | Where-Object { $_ -like "$Model*" }).Count -gt 0) {
    Say "模型已存在：$Model（跳过拉取）" Green
} else {
    Say "拉取模型 $Model（首次要下几 GB，慢的话耐心等；Ctrl+C 可中断，重跑会续传）..." Cyan
    & $ollama pull $Model
    if ($LASTEXITCODE -ne 0) { Say "拉取失败（退出码 $LASTEXITCODE）。可重跑本脚本续传。" Red; exit 1 }
    Say "模型拉取完成" Green
}

# ---- 4) 验证 ----
$models = @()
try { $models = @((Invoke-RestMethod -Uri 'http://127.0.0.1:11434/api/tags' -TimeoutSec 10).models | ForEach-Object { [string]$_.name }) } catch { }
if ($models.Count -eq 0) { Say "API 能连上但列不出模型，检查 OLLAMA_MODELS 是否指错目录。" Red; exit 1 }

Say ""
Say "本机视觉模型：$($models -join ', ')" Green
Say ""
Say "现在直接跑 sd-inject.ps1 就会用上脸/手质检：素体迭代会换 seed 重试到过关，最终图按迭代次数取最高分。" White
Say "  .\sd-inject.ps1                      # 表单里的 Denoising / 底图 都可用" darkgray
Say "  .\sd-inject.ps1 -VlmModel $Model     # 显式指定质检模型" darkgray
Say ""
Say "留点余量：8G 显存同时跑 SD 与 4b 视觉模型比较紧，质检偶尔会慢（脚本会自动降级，不会卡死出图）。" darkgray
