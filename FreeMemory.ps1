<#
.SYNOPSIS
    一键释放内存工具

.DESCRIPTION
    关闭后台所有非必要进程，仅保留：
      1) 显卡驱动相关进程 (NVIDIA / AMD / Intel)
      2) 壁纸类进程 (Wallpaper Engine 等)
      3) Steam 相关进程
    同时保护系统关键进程，避免系统崩溃。
    适用于：想快速腾出内存、关闭一堆后台程序但不想手动一个个关的场景。

.NOTES
    运行方式：右键 -> 用 PowerShell 运行，或在窗口中执行
      powershell -ExecutionPolicy Bypass -File "FreeMemory.ps1"
    建议：执行前先保存好其它程序里的工作（浏览器、文档等会被关闭）。
#>

#Requires -Version 5.1
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

#region ---------- 保护名单（这些进程不会被关闭） ----------

# 显卡驱动相关进程（NVIDIA / AMD / Intel）
$gpuDrivers = @(
    'nvcontainer', 'nvsphelper64', 'nvsphelper', 'nvidia web helper', 'nvidia-smi',
    'nvdisplay.container', 'nvstreamsvc', 'nvaudiosvr', 'nvcplui', 'nvwddns',
    'nvsmartmaxapp', 'nvbackend', 'nvbroadcast', 'nvtray',
    'amdrsserv', 'radeonsoftware', 'amdow', 'cncmd', 'mom', 'ccc',
    'atiesrxx', 'atieclxx', 'amdlogserv', 'amdlink', 'radeonsoftware',
    'igfxcuiservice', 'igfxem', 'igfxtray', 'intelcphdcpsvc', 'intelcphcpsvc'
)

# 壁纸类进程（Wallpaper Engine 等）
$wallpaper = @(
    'wallpaper32', 'wallpaper64', 'wallpaper_engine', 'wallpaperengine',
    'ui32', 'wallpaperdesktop', 'komorebi', 'lively', 'livelyinstall'
)

# Steam 相关进程
$steam = @(
    'steam', 'steamwebhelper', 'gameoverlayui', 'steamerrorreporter',
    'streaming_client', 'steamservice'
)

# 系统关键进程（绝不关闭，关闭会导致系统不稳定或蓝屏）
$systemProtected = @(
    'system', 'system idle process', 'csrss', 'wininit', 'services', 'lsass',
    'lsaiso', 'smss', 'winlogon', 'dwm', 'taskhost', 'taskhostw', 'svchost',
    'conhost', 'runtimebroker', 'sihost', 'fontdrvhost', 'dashost', 'spoolsv',
    'memory compression', 'registry', 'secure system', 'wudfhost', 'dllhost',
    'audiodg', 'ctfmon', 'searchui', 'searchindexer', 'shellexperiencehost',
    'applicationframehost', 'textinputhost', 'startmenuexperiencehost',
    'windows internal notification', 'csrss', 'wininit', 'smss', 'lsass'
)

#endregion

#region ---------- 共享状态 ----------
$script:candidates = @()      # 待关闭进程列表
$script:grid      = $null     # DataGridView
$script:lblTotal  = $null     # 内存总计标签
$script:lblStatus = $null     # 状态标签
$script:chkAggr   = $null     # 激进模式复选框
$script:txtExtra  = $null     # 额外保留文本框
#endregion

function Get-NormalizedName($raw) {
    return ($raw -replace '\.exe$', '' -replace '\s+', ' ').ToLower().Trim()
}

function Get-Candidates {
    param([bool]$aggressive)

    $keep = @{}
    foreach ($n in ($gpuDrivers + $wallpaper + $steam)) { $keep[(Get-NormalizedName $n)] = $true }

    # 用户在文本框里额外指定的保留进程
    if ($script:txtExtra -and $script:txtExtra.Text) {
        foreach ($line in $script:txtExtra.Text -split "`r?`n") {
            $ln = (Get-NormalizedName $line)
            if ($ln) { $keep[$ln] = $true }
        }
    }

    $protect = @{}
    foreach ($n in $systemProtected) { $protect[(Get-NormalizedName $n)] = $true }
    # 默认保护资源管理器；仅在“激进模式”下才允许关闭
    if (-not $aggressive) { $protect[(Get-NormalizedName 'explorer')] = $true }

    $currentPid = $PID
    $list = @()
    $procs = Get-Process -ErrorAction SilentlyContinue
    foreach ($p in $procs) {
        $name = Get-NormalizedName $p.ProcessName
        if ([string]::IsNullOrEmpty($name)) { continue }
        if ($keep.ContainsKey($name)) { continue }
        if ($protect.ContainsKey($name)) { continue }
        if ($p.Id -eq $currentPid) { continue }   # 不要自杀

        $memMB = 0
        try { $memMB = [math]::Round($p.WorkingSet / 1MB, 1) } catch { continue }
        if ($memMB -le 0) { continue }

        $list += [PSCustomObject]@{
            Name  = $p.ProcessName
            PID   = $p.Id
            MemMB = $memMB
        }
    }
    # 按占用内存从大到小排序，方便查看
    $list | Sort-Object -Property MemMB -Descending
}

function Update-Grid {
    param([bool]$aggressive)
    $script:candidates = Get-Candidates -aggressive $aggressive
    $script:grid.Rows.Clear()
    $total = 0
    foreach ($c in $script:candidates) {
        $script:grid.Rows.Add($c.Name, $c.PID, $c.MemMB)
        $total += $c.MemMB
    }
    $script:lblTotal.Text = "待关闭进程：$($script:candidates.Count) 个 ｜ 预计释放内存（估值）：$('{0:N1}' -f $total) MB"
    $script:lblStatus.Text = '扫描完成，点击“一键释放内存”执行。'
}

function Start-Scan { Update-Grid -aggressive $script:chkAggr.Checked }

function Start-FreeMemory {
    if (-not $script:candidates -or $script:candidates.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show('当前没有可关闭的进程。', '提示', 'OK', 'Information')
        return
    }
    $total = ($script:candidates | Measure-Object -Property MemMB -Sum).Sum
    $msg = "将关闭 $($script:candidates.Count) 个进程，`n预计释放约 $($total.ToString('N1')) MB 内存。`n`n注意：浏览器、文档等其它程序会被关闭，请先保存工作。`n`n确定继续？"
    $r = [System.Windows.Forms.MessageBox]::Show($msg, '确认释放内存', 'YesNo', 'Warning')
    if ($r -ne 'Yes') { return }

    $freed = 0
    $failed = 0
    foreach ($item in $script:candidates) {
        try {
            Stop-Process -Id $item.PID -Force -ErrorAction Stop
            $freed += $item.MemMB
        } catch {
            $failed++
        }
    }
    $script:lblStatus.Text = "已关闭 $($script:candidates.Count - $failed) 个进程，释放约 $($freed.ToString('N1')) MB；失败 $failed 个。"
    [System.Windows.Forms.MessageBox]::Show(
        "释放完成！`n成功关闭：$($script:candidates.Count - $failed) 个`n释放约：$($freed.ToString('N1')) MB`n失败：$failed 个（多为系统保护或权限不足）",
        '完成', 'OK', 'Information')
    # 重新扫描，刷新界面
    Update-Grid -aggressive $script:chkAggr.Checked
}

function Restart-Explorer {
    try {
        Start-Process explorer.exe
        $script:lblStatus.Text = '已重新启动资源管理器（桌面/任务栏）。'
    } catch {
        $script:lblStatus.Text = "重启资源管理器失败：$_"
    }
}

#region ---------- 构建界面 ----------
$form = New-Object System.Windows.Forms.Form
$form.Text = '一键释放内存工具'
$form.Size = New-Object System.Drawing.Size(900, 640)
$form.StartPosition = 'CenterScreen'
$form.Font = New-Object System.Drawing.Font('Microsoft YaHei', 9)
$form.BackColor = [System.Drawing.Color]::FromArgb(245, 247, 250)

# 标题
$lblTitle = New-Object System.Windows.Forms.Label
$lblTitle.Location = New-Object System.Drawing.Point(12, 10)
$lblTitle.Size = New-Object System.Drawing.Size(860, 22)
$lblTitle.Text = '关闭后台所有非必要进程，仅保留：显卡驱动 / 壁纸 / Steam'
$lblTitle.Font = New-Object System.Drawing.Font('Microsoft YaHei', 11, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($lblTitle)

# 扫描按钮
$btnScan = New-Object System.Windows.Forms.Button
$btnScan.Location = New-Object System.Drawing.Point(12, 40)
$btnScan.Size = New-Object System.Drawing.Size(120, 30)
$btnScan.Text = '扫描进程'
$btnScan.Add_Click({ Start-Scan })
$form.Controls.Add($btnScan)

# 激进模式复选框
$script:chkAggr = New-Object System.Windows.Forms.CheckBox
$script:chkAggr.Location = New-Object System.Drawing.Point(150, 44)
$script:chkAggr.Size = New-Object System.Drawing.Size(280, 24)
$script:chkAggr.Text = '激进模式（同时关闭资源管理器 explorer）'
$script:chkAggr.Add_CheckedChanged({ Start-Scan })
$form.Controls.Add($script:chkAggr)

# 总计标签
$script:lblTotal = New-Object System.Windows.Forms.Label
$script:lblTotal.Location = New-Object System.Drawing.Point(12, 78)
$script:lblTotal.Size = New-Object System.Drawing.Size(860, 20)
$script:lblTotal.Text = '点击“扫描进程”开始。'
$form.Controls.Add($script:lblTotal)

# 数据网格
$script:grid = New-Object System.Windows.Forms.DataGridView
$script:grid.Location = New-Object System.Drawing.Point(12, 104)
$script:grid.Size = New-Object System.Drawing.Size(860, 350)
$script:grid.ReadOnly = $true
$script:grid.AllowUserToAddRows = $false
$script:grid.AllowUserToDeleteRows = $false
$script:grid.AutoSizeColumnsMode = 'Fill'
$script:grid.RowHeadersVisible = $false
$script:grid.ScrollBars = 'Vertical'
$null = $script:grid.Columns.Add('colName', '进程名')
$null = $script:grid.Columns.Add('colPid', 'PID')
$null = $script:grid.Columns.Add('colMem', '内存(MB)')
$script:grid.Columns['colMem'].DefaultCellStyle.Alignment = 'MiddleRight'
$form.Controls.Add($script:grid)

# 额外保留标签
$lblExtra = New-Object System.Windows.Forms.Label
$lblExtra.Location = New-Object System.Drawing.Point(12, 466)
$lblExtra.Size = New-Object System.Drawing.Size(860, 18)
$lblExtra.Text = '额外保留的进程（每行一个，如：chrome / wechat / dingtalk）：'
$form.Controls.Add($lblExtra)

# 额外保留文本框
$script:txtExtra = New-Object System.Windows.Forms.TextBox
$script:txtExtra.Location = New-Object System.Drawing.Point(12, 488)
$script:txtExtra.Size = New-Object System.Drawing.Size(860, 56)
$script:txtExtra.Multiline = $true
$script:txtExtra.ScrollBars = 'Vertical'
$form.Controls.Add($script:txtExtra)

# 释放按钮
$btnFree = New-Object System.Windows.Forms.Button
$btnFree.Location = New-Object System.Drawing.Point(12, 552)
$btnFree.Size = New-Object System.Drawing.Size(160, 34)
$btnFree.Text = '一键释放内存'
$btnFree.BackColor = [System.Drawing.Color]::FromArgb(220, 80, 80)
$btnFree.ForeColor = [System.Drawing.Color]::White
$btnFree.Font = New-Object System.Drawing.Font('Microsoft YaHei', 10, [System.Drawing.FontStyle]::Bold)
$btnFree.Add_Click({ Start-FreeMemory })
$form.Controls.Add($btnFree)

# 重启桌面按钮
$btnExplorer = New-Object System.Windows.Forms.Button
$btnExplorer.Location = New-Object System.Drawing.Point(190, 552)
$btnExplorer.Size = New-Object System.Drawing.Size(160, 34)
$btnExplorer.Text = '重启桌面 (explorer)'
$btnExplorer.Add_Click({ Restart-Explorer })
$form.Controls.Add($btnExplorer)

# 状态标签
$script:lblStatus = New-Object System.Windows.Forms.Label
$script:lblStatus.Location = New-Object System.Drawing.Point(370, 558)
$script:lblStatus.Size = New-Object System.Drawing.Size(500, 28)
$script:lblStatus.Text = ''
$form.Controls.Add($script:lblStatus)

#endregion

# 设置窗体图标（与脚本同目录的 .ico；缺失时不影响功能）
$iconFile = Join-Path $PSScriptRoot 'memory-cleanup-icon.ico'
if (Test-Path $iconFile) {
    try { $form.Icon = [System.Drawing.Icon]::new($iconFile) } catch { }
}

# 启动即扫描一次
Update-Grid -aggressive $false
[System.Windows.Forms.Application]::EnableVisualStyles() | Out-Null
[System.Windows.Forms.Application]::Run($form)
