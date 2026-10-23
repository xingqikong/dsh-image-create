# FORK-NOTES · 本 fork 与上游 0.9.8 的差异

上游：[savinglighting/dsh-sd-bridge-guard](https://github.com/savinglighting/dsh-sd-bridge-guard) v0.9.8（MIT）。
本仓库只改了 `sd-inject.ps1`（C 档本地注入），并新增 `install-ollama.ps1` 与 `tools/apply-fix.ps1`；`sd-bridge.js`、`sd-direct.ps1`、`install-sd.ps1` 与上游一致（仅 `package.json` 的仓库地址指向本 fork）。

---

## 1. Denoising 选了 >0 却"回到 0"

**现象**：表单里 Denoising 选 0.5，出图还是文生图。

**根因**：Denoising 只对图生图生效，而图生图的底图**只能**来自"素体自检迭代"的产出；素体迭代依赖本地视觉模型，模型没装/没起时直接返回空 → 旧代码静默退回文生图（Denoising 等于 0）。

**修复**：
- 新增 `Invoke-BaseOnce`：Denoising > 0 但没有底图时，现场补出一张素体基底图（不质检、只一张），再走图生图。
- 表单确定后立即回显实际参数，值有没有生效当场可见。

## 2. C 档表单没有"底图"入口

**修复**：表单新增「底图：」一行 + 「浏览…」（`OpenFileDialog`，默认目录 `SD-Picture`），并支持命令行 `-InitImage`。
选中底图后自动：

1. 跳过素体自检迭代（`$baseWin` 直接指向你的图）
2. 按底图宽高比选中「比例」、按短边选中「画质」
3. Denoising 为 0 时自动抬到 `0.55`
4. 不再强行追加 `full body`

## 3. SD 冷启动时脚本卡死（表单永不弹出）

**现象**：SD 没在跑时，控制台停在「首次使用：正在拉起 Stable Diffusion…」，等十几分钟也不弹表单。

**根因**：预热写成了 `$preheatOut = & powershell <sd-direct.ps1> -StartOnly 2>&1`。SD 进程继承了这个 stdout 管道，SD 一直活着 → 管道永不关闭 → 父进程死等 EOF。

**修复**：预热改为直接调用、**不捕获输出**。子进程输出照常打到控制台。

## 4. 没有"出几张让我挑"

**修复**：新增多选模式——表单勾选框「多选：出满 N 张后弹列表让我挑」，或命令行 `-PickAll`。
配合 `Invoke-FinalIterate -ForceAll`（不因质检提前达标而停），出满后用 `Show-ImagePicker` 弹列表勾选保留；取消 = 全部保留。

## 5. 质检服务没起就静默跳过

**修复**：新增 `Start-OllamaIfNeeded`——质检前先探测 `/v1/models`，没起来就用 `ollama serve` 拉起并等待就绪；仍不行才跳过。

## 6. 默认质检模型与 SD 抢显存

上游默认 `qwen3-vl:8b`（约 5.2 GB），8 GB 显卡和 SD（约 2.4 GB）同时驻留会爆显存。
**修复**：默认改为 `qwen3-vl:4b`（约 3.3 GB），可用 `-VlmModel` 覆盖。

## 7. 参数解析太脆

- 迭代次数：支持「8」「8 轮」
- Denoising：全角数字（０．７）、中文逗号（0，4）自动归一；非数字给一行黄色警告而不是静默归零
- Denoising 下拉档位扩充到 0.1–0.95 共 17 档

## 8. 选错参数要等几分钟才知道

表单确定后立即打印一行实际取到的参数：

```
表单已确认：迭代 3 次 | Denoising 0.55（图生图） | 比例 2:3 | 画风 二次元 | 画质 1024p | LoRA 不用 | 模型 当前模型 | 底图 你的底图 | 命名 (自动生成)
```

## 9. 有底图时仍强行追加 full body

原逻辑：正向提示词里没有景别词就补 `full body`。有底图时会把半身/特写构图强行拉成全身。
**修复**：有底图时不追加。

---

## 编码约定（重要）

`sd-inject.ps1` / `sd-direct.ps1` 必须保存为 **UTF-8 with BOM**。PowerShell 5.1 读无 BOM 的中文会按 GBK 解码，字符串里的引号被撕开，直接语法报错。

## 新增文件

| 文件 | 作用 |
| --- | --- |
| `install-ollama.ps1` | 一键安装 Ollama + 视觉模型（多镜像下载、静默安装、拉起服务、拉模型、验证） |
| `tools/apply-fix.ps1` | 把本仓库的修复重新打进任意一份 `sd-inject.ps1`（插件升级覆盖后重打） |

`tools/apply-fix.ps1` 用法：

```powershell
.\tools\apply-fix.ps1 -Path "C:\Users\<你>\.dsh\profiles\desktop\node_modules\dsh-sd-bridge-guard\sd-inject.ps1"
```

脚本会逐条校验锚点（命中次数必须为 1），任一不匹配就报错退出，不会产出半成品文件。
