# ============================================================
# config.ps1 - sdock layout editor (WinForms GUI)
#
# The only file it edits: @Resources\layout.ini
# Save pipeline: backup layout.ini -> rewrite it -> Render-Skins (in-process)
#                -> send bangs to Rainmeter.exe
#
# Run:  powershell -NoProfile -ExecutionPolicy Bypass -File config.ps1
# ============================================================

$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# 任何 handler 里漏出的异常都在这里兜住，避免弹出 .NET「JIT 调试」崩溃对话框。
[System.Windows.Forms.Application]::Add_ThreadException({
    param($sender, $e)
    $inner = $e.Exception
    while ($null -ne $inner.InnerException) { $inner = $inner.InnerException }
    [void][System.Windows.Forms.MessageBox]::Show(
        ('这一步没有完成：' + $e.Exception.Message + "`r`n`r`n内层原因：" + $inner.Message),
        'sdock 配置编辑器', 'OK', 'Error')
    $e.HandleException = $true
})

$resourcesDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$skinBasePath = Split-Path -Parent $resourcesDir
$layoutPath   = Join-Path $resourcesDir 'layout.ini'
$varsPath     = Join-Path $resourcesDir 'Variables.inc'

if (-not (Test-Path $layoutPath)) { throw "找不到 layout.ini: $layoutPath" }
if (-not (Test-Path $varsPath))   { throw "找不到 Variables.inc: $varsPath" }

# layout 解析/写回与皮肤渲染都在 render.ps1（只定义函数），本文件只管界面。
. (Join-Path $resourcesDir 'render.ps1')

# ------------------------------------------------------------
# roots (IconRoot / LinkRoot come from layout.ini [sdock])
# ------------------------------------------------------------
$globalCfg = @{ IconRoot = '#@#ico'; LinkRoot = '#@#link' }

function Expand-Root([string]$v) {
    if ($v.StartsWith('#@#')) { return (Join-Path $resourcesDir $v.Substring(3)) }
    return $v
}

$rainExe = $null
$candidates = @(
    'D:\Program Files\Rainmeter\Rainmeter.exe',
    'C:\Program Files\Rainmeter\Rainmeter.exe'
)
if (${env:ProgramFiles}) { $candidates += (Join-Path ${env:ProgramFiles} 'Rainmeter\Rainmeter.exe') }
foreach ($c in $candidates) { if ($c -and (Test-Path $c)) { $rainExe = $c; break } }

# ------------------------------------------------------------
# read / write layout.ini
# ------------------------------------------------------------
$script:docks   = [ordered]@{}
$script:current = -1
$script:loading = $false
# 上一次真正落盘（写 layout.ini + 渲染）时的 dock 名集合。
# 保存时用它和当前模型做差集，才知道哪些皮肤被删了、哪些是新增。
$script:savedNames = @()

function Read-Layout {
    $m = Read-SdockLayout $layoutPath
    $script:docks = $m.Docks
    foreach ($k in $m.Global.Keys) { $globalCfg[$k] = $m.Global[$k] }
    $script:savedNames = @($m.Docks.Keys)
}

function Write-Layout { Write-SdockLayout $layoutPath $script:docks $globalCfg }

# ------------------------------------------------------------
# helpers
# ------------------------------------------------------------
function Clean([object]$v) {
    if ($null -eq $v) { return '' }
    return ([string]$v).Trim().Replace('|', ' ')
}

function Current-Dock {
    if ($script:current -lt 0 -or $script:current -ge $script:docks.Count) { return $null }
    return @($script:docks.Values)[$script:current]
}

function New-Label([string]$text, [int]$x, [int]$y, [int]$w, [int]$h) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $text
    $l.Location = New-Object System.Drawing.Point($x, $y)
    $l.Size = New-Object System.Drawing.Size($w, $h)
    return $l
}

function New-Button([string]$text, [int]$x, [int]$y, [int]$w, [int]$h) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $text
    $b.Location = New-Object System.Drawing.Point($x, $y)
    $b.Size = New-Object System.Drawing.Size($w, $h)
    return $b
}

function Show-Input([string]$title, [string]$prompt, [string]$default) {
    $dlg = New-Object System.Windows.Forms.Form
    $dlg.Text = $title
    $dlg.ClientSize = New-Object System.Drawing.Size(320, 120)
    $dlg.FormBorderStyle = 'FixedDialog'
    $dlg.MaximizeBox = $false
    $dlg.MinimizeBox = $false
    $dlg.ShowInTaskbar = $false
    $dlg.StartPosition = 'CenterParent'
    $dlg.Font = New-Object System.Drawing.Font('Segoe UI', 9.0)
    $lb = New-Label $prompt 12 12 296 18
    $tb = New-Object System.Windows.Forms.TextBox
    $tb.Location = New-Object System.Drawing.Point(12, 36)
    $tb.Size = New-Object System.Drawing.Size(296, 24)
    $tb.Text = $default
    $ok = New-Button '确定' 152 72 74 28
    $cancel = New-Button '取消' 234 72 74 28
    $ok.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $cancel.DialogResult = [System.Windows.Forms.DialogResult]::Cancel
    $dlg.AcceptButton = $ok
    $dlg.CancelButton = $cancel
    $dlg.Controls.Add($lb) | Out-Null
    $dlg.Controls.Add($tb) | Out-Null
    $dlg.Controls.Add($ok) | Out-Null
    $dlg.Controls.Add($cancel) | Out-Null
    $tb.SelectAll()
    $res = $dlg.ShowDialog($form)
    $txt = $tb.Text
    $dlg.Dispose()
    if ($res -eq [System.Windows.Forms.DialogResult]::OK) { return $txt }
    return $null
}

function Set-Status([string]$text, [string]$color) {
    $lblStatus.Text = $text
    if ($color -eq 'red') { $lblStatus.ForeColor = [System.Drawing.Color]::Firebrick }
    elseif ($color -eq 'green') { $lblStatus.ForeColor = [System.Drawing.Color]::DarkGreen }
    else { $lblStatus.ForeColor = [System.Drawing.Color]::Black }
}

# ------------------------------------------------------------
# form
# ------------------------------------------------------------
$form = New-Object System.Windows.Forms.Form
$form.Text = 'sdock 配置编辑器'
$form.ClientSize = New-Object System.Drawing.Size(1000, 700)
$form.FormBorderStyle = 'FixedSingle'
$form.MaximizeBox = $false
$form.StartPosition = 'CenterScreen'
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9.0)

# ---------- left: dock list ----------
$form.Controls.Add((New-Label 'Dock 列表（左侧选中一个，右侧编辑它的条目）' 12 9 258 18))

$lstDocks = New-Object System.Windows.Forms.ListBox
$lstDocks.Location = New-Object System.Drawing.Point(12, 32)
$lstDocks.Size = New-Object System.Drawing.Size(258, 300)
$lstDocks.HorizontalScrollbar = $true
$form.Controls.Add($lstDocks) | Out-Null

$btnDockAdd    = New-Button '新建 Dock'    12  342 122 28
$btnDockDel    = New-Button '删除 Dock'    148 342 122 28
$btnDockUp     = New-Button '上移'         12  376 122 28
$btnDockDown   = New-Button '下移'         148 376 122 28
$form.Controls.Add($btnDockAdd) | Out-Null
$form.Controls.Add($btnDockDel) | Out-Null
$form.Controls.Add($btnDockUp) | Out-Null
$form.Controls.Add($btnDockDown) | Out-Null

$form.Controls.Add((New-Label 'Dock 显示标题' 12 416 258 18))

$txtTitle = New-Object System.Windows.Forms.TextBox
$txtTitle.Location = New-Object System.Drawing.Point(12, 437)
$txtTitle.Size = New-Object System.Drawing.Size(258, 24)
$form.Controls.Add($txtTitle) | Out-Null

$form.Controls.Add((New-Label '每行列数（1 - 12）' 12 470 258 18))

$numCols = New-Object System.Windows.Forms.NumericUpDown
$numCols.Location = New-Object System.Drawing.Point(12, 491)
$numCols.Size = New-Object System.Drawing.Size(80, 24)
$numCols.Minimum = 1
$numCols.Maximum = 12
$numCols.DecimalPlaces = 0
$form.Controls.Add($numCols) | Out-Null

$lblItems = New-Label '条目数：0' 12 526 258 18
$form.Controls.Add($lblItems) | Out-Null

$lblHint = New-Label ("提示：图标若选到 ico\ 目录之外会自动复制进皮肤；" + "链接优先记录 link\ 下的相对路径，选目录外的文件则记录绝对路径。`r`n改完点右下角「保存并渲染」。") 12 552 258 60
$form.Controls.Add($lblHint) | Out-Null

# ---------- right: item grid ----------
$form.Controls.Add((New-Label '条目（标签可直接双击编辑；图标 / 链接用下方按钮改）' 290 9 698 18))

$grid = New-Object System.Windows.Forms.DataGridView
$grid.Location = New-Object System.Drawing.Point(290, 32)
$grid.Size = New-Object System.Drawing.Size(698, 500)
$grid.AllowUserToAddRows = $false
$grid.AllowUserToDeleteRows = $false
$grid.AllowUserToResizeRows = $false
$grid.RowHeadersVisible = $false
$grid.MultiSelect = $false
$grid.SelectionMode = [System.Windows.Forms.DataGridViewSelectionMode]::FullRowSelect
$grid.AutoSizeColumnsMode = [System.Windows.Forms.DataGridViewAutoSizeColumnsMode]::Fill
$grid.ColumnHeadersHeightSizeMode = [System.Windows.Forms.DataGridViewColumnHeadersHeightSizeMode]::DisableResizing
$grid.EditMode = [System.Windows.Forms.DataGridViewEditMode]::EditOnKeystrokeOrF2
$grid.Anchor = 'Top,Left,Right,Bottom'

foreach ($c in @(
        @{ H = '#';    W = 5;  Ro = $true  },
        @{ H = '标签'; W = 18; Ro = $false },
        @{ H = '图标'; W = 24; Ro = $true  },
        @{ H = '链接'; W = 53; Ro = $true  }
    )) {
    $col = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
    $col.HeaderText = $c.H
    $col.FillWeight = $c.W
    $col.ReadOnly = $c.Ro
    $grid.Columns.Add($col) | Out-Null
}
$form.Controls.Add($grid) | Out-Null

$btnItemAdd  = New-Button '添加条目' 290 542 92 28
$btnItemDel  = New-Button '删除条目' 388 542 92 28
$btnItemUp   = New-Button '上移'     486 542 56 28
$btnItemDown = New-Button '下移'     548 542 56 28
$btnItemTop  = New-Button '置顶'     610 542 56 28
$btnItemBot  = New-Button '置底'     672 542 56 28
$btnSetIcon  = New-Button '更换图标' 734 542 92 28
$btnSetLink  = New-Button '更换链接' 832 542 92 28
foreach ($b in @($btnItemAdd, $btnItemDel, $btnItemUp, $btnItemDown, $btnItemTop, $btnItemBot, $btnSetIcon, $btnSetLink)) {
    $b.Anchor = 'Bottom,Left,Right'
    $form.Controls.Add($b) | Out-Null
}

# ---------- bottom: save ----------
$btnSave = New-Button '保存并渲染' 290 586 140 40
$btnSave.Font = New-Object System.Drawing.Font('Segoe UI', 10.0, [System.Drawing.FontStyle]::Bold)
$btnSave.Anchor = 'Bottom,Left'
$form.Controls.Add($btnSave) | Out-Null

$lblStatus = New-Label '就绪' 444 586 544 40
$lblStatus.Anchor = 'Bottom,Left,Right'
$form.Controls.Add($lblStatus) | Out-Null

# ------------------------------------------------------------
# view <-> model
# ------------------------------------------------------------
function Update-DockList {
    $script:loading = $true
    $lstDocks.Items.Clear()
    foreach ($d in $script:docks.Values) {
        $lstDocks.Items.Add(('{0}   ({1} 项)' -f $d.Name, $d.Items.Count)) | Out-Null
    }
    if ($script:current -ge $lstDocks.Items.Count) { $script:current = $lstDocks.Items.Count - 1 }
    if ($script:current -ge 0) { $lstDocks.SelectedIndex = $script:current }
    elseif ($lstDocks.Items.Count -gt 0) { $lstDocks.SelectedIndex = 0 }
    $script:loading = $false
}

function Load-Dock([int]$idx) {
    if ($idx -lt 0 -or $idx -ge $script:docks.Count) { return }
    $script:current = $idx
    $d = @($script:docks.Values)[$idx]
    $script:loading = $true
    $txtTitle.Text = $d.Title
    $cv = [int]$d.Columns
    if ($cv -lt 1) { $cv = 1 }
    if ($cv -gt 12) { $cv = 12 }
    $numCols.Value = $cv
    $grid.Rows.Clear()
    $i = 0
    foreach ($it in $d.Items) {
        $i++
        $grid.Rows.Add(@([string]$i, $it.Name, $it.Icon, $it.Link)) | Out-Null
    }
    $script:loading = $false
    $lblItems.Text = '条目数：' + $d.Items.Count
}

function Save-Grid {
    $d = Current-Dock
    if ($null -eq $d) { return }
    $grid.EndEdit()
    $arr = New-Object System.Collections.Generic.List[object]
    for ($i = 0; $i -lt $grid.Rows.Count; $i++) {
        $r = $grid.Rows[$i]
        if ($r.IsNewRow) { continue }
        $arr.Add([pscustomobject]@{
                Name = Clean $r.Cells[1].Value
                Icon = Clean $r.Cells[2].Value
                Link = Clean $r.Cells[3].Value
            }) | Out-Null
    }
    $d.Items.Clear()
    foreach ($it in $arr) { $d.Items.Add($it) | Out-Null }
}

function Selected-Row {
    if ($grid.CurrentRow -eq $null) { return -1 }
    return $grid.CurrentRow.Index
}

# 默认（上移 / 下移）：两个位置互换。
# -Shift（置顶 / 置底）：取出 $from 插到 $to，中间的条目整体顺移。
function Reorder-Items([int]$from, [int]$to, [switch]$Shift) {
    $d = Current-Dock
    if ($null -eq $d) { return $false }
    if ($from -lt 0 -or $from -ge $d.Items.Count) { return $false }
    if ($to -lt 0 -or $to -ge $d.Items.Count) { return $false }
    if ($from -eq $to) { return $false }
    if ($Shift) {
        $it = $d.Items[$from]
        $d.Items.RemoveAt($from)
        $d.Items.Insert($to, $it)
    } else {
        $tmp = $d.Items[$from]
        $d.Items[$from] = $d.Items[$to]
        $d.Items[$to] = $tmp
    }
    return $true
}

function Move-GridItem([int]$from, [int]$to, [switch]$Shift) {
    if (-not (Reorder-Items $from $to -Shift:$Shift)) { return }
    Load-Dock $script:current
    Update-DockList
    if ($to -ge 0 -and $to -lt $grid.Rows.Count) {
        $grid.ClearSelection()
        $grid.Rows[$to].Selected = $true
        $grid.CurrentCell = $grid.Rows[$to].Cells[1]
    }
}

function Rebuild-Docks([object[]]$arr) {
    $nd = [ordered]@{}
    foreach ($d in $arr) { $nd[$d.Name] = $d }
    $script:docks = $nd
}

# ------------------------------------------------------------
# icon / link pickers
# ------------------------------------------------------------
$iconRootAbs = Expand-Root $globalCfg['IconRoot']
$linkRootAbs = Expand-Root $globalCfg['LinkRoot']

function Resolve-Icon([string]$picked) {
    $full = [System.IO.Path]::GetFullPath($picked)
    $root = $iconRootAbs.TrimEnd('\') + '\'
    if ($full.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $full.Substring($root.Length)
    }
    if (-not (Test-Path $iconRootAbs)) { New-Item -ItemType Directory -Path $iconRootAbs -Force | Out-Null }
    $base = [System.IO.Path]::GetFileNameWithoutExtension($full)
    $ext = [System.IO.Path]::GetExtension($full)
    $dest = Join-Path $iconRootAbs ($base + $ext)
    $n = 1
    while ((Test-Path $dest) -and ((Get-FileHash $dest -Algorithm SHA1).Hash -ne (Get-FileHash $full -Algorithm SHA1).Hash)) {
        $dest = Join-Path $iconRootAbs ('{0}_{1}{2}' -f $base, $n, $ext)
        $n++
    }
    if (-not (Test-Path $dest)) { Copy-Item $full $dest }
    return [System.IO.Path]::GetFileName($dest)
}

function Resolve-Link([string]$picked) {
    $full = [System.IO.Path]::GetFullPath($picked)
    $root = $linkRootAbs.TrimEnd('\') + '\'
    if ($full.StartsWith($root, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $full.Substring($root.Length)
    }
    return $full
}

function Set-Cell([int]$row, [int]$col, [string]$value) {
    $grid.Rows[$row].Cells[$col].Value = $value
}

function Pick-File([string]$title, [string]$filter, [string]$initialDir) {
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Title = $title
    $dlg.Filter = $filter
    if ($initialDir -and (Test-Path $initialDir)) { $dlg.InitialDirectory = $initialDir }
    if ($dlg.ShowDialog($form) -eq [System.Windows.Forms.DialogResult]::OK) { return $dlg.FileName }
    return $null
}

# ------------------------------------------------------------
# events
# ------------------------------------------------------------
$lstDocks.Add_SelectedIndexChanged({
    if ($script:loading) { return }
    Save-Grid
    Load-Dock $lstDocks.SelectedIndex
})

$txtTitle.Add_TextChanged({
    if ($script:loading) { return }
    $d = Current-Dock
    if ($d) { $d.Title = $txtTitle.Text }
})

$numCols.Add_ValueChanged({
    if ($script:loading) { return }
    $d = Current-Dock
    if ($d) { $d.Columns = [int]$numCols.Value }
})

$btnDockAdd.Add_Click({
    Save-Grid
    $name = Show-Input '新建 Dock' 'Dock 名（只允许英文字母 / 数字 / - / _，它同时是皮肤文件夹名）：' 'NewDock'
    if ($null -eq $name) { return }
    $name = $name.Trim()
    if ($name -notmatch '^[A-Za-z0-9_-]+$') {
        [void][System.Windows.Forms.MessageBox]::Show('Dock 名只能用英文字母、数字、连字符和下划线。', 'sdock')
        return
    }
    if ($script:docks.Contains($name)) {
        [void][System.Windows.Forms.MessageBox]::Show("已存在同名 Dock：$name", 'sdock')
        return
    }
    $new = [pscustomobject]@{
        Name = $name; Title = $name; Columns = 3
        Items = (New-Object System.Collections.Generic.List[object])
    }
    $arr = @($script:docks.Values) + $new
    Rebuild-Docks $arr
    $script:current = $arr.Count - 1
    Update-DockList
    Load-Dock $script:current
    Set-Status "已新建 $name（还没有条目），保存后 Rainmeter 会自动加载它。" 'black'
})

$btnDockDel.Add_Click({
    $d = Current-Dock
    if ($null -eq $d) { return }
    $res = [System.Windows.Forms.MessageBox]::Show(
        "确定删除 Dock「$($d.Name)」及其 $($d.Items.Count) 个条目吗？`r`n保存后会卸载该皮肤，并删除皮肤文件 $($d.Name)\$($d.Name).ini（文件夹空了也一并删掉）。`r`n@Resources 里的图标和快捷方式副本不会动，layout.ini 会先备份。",
        'sdock', 'YesNo', 'Warning')
    if ($res -ne [System.Windows.Forms.DialogResult]::Yes) { return }
    $arr = @($script:docks.Values | Where-Object { $_.Name -ne $d.Name })
    Rebuild-Docks $arr
    if ($script:current -ge $arr.Count) { $script:current = $arr.Count - 1 }
    Update-DockList
    if ($arr.Count -gt 0) { Load-Dock $script:current } else {
        $grid.Rows.Clear()
        $lblItems.Text = '条目数：0'
    }
})

$btnDockUp.Add_Click({
    if ($script:current -le 0) { return }
    Save-Grid
    $arr = @($script:docks.Values)
    $tmp = $arr[$script:current]
    $arr[$script:current] = $arr[$script:current - 1]
    $arr[$script:current - 1] = $tmp
    Rebuild-Docks $arr
    $script:current = $script:current - 1
    Update-DockList
    Load-Dock $script:current
})

$btnDockDown.Add_Click({
    if ($script:current -lt 0 -or $script:current -ge ($script:docks.Count - 1)) { return }
    Save-Grid
    $arr = @($script:docks.Values)
    $tmp = $arr[$script:current]
    $arr[$script:current] = $arr[$script:current + 1]
    $arr[$script:current + 1] = $tmp
    Rebuild-Docks $arr
    $script:current = $script:current + 1
    Update-DockList
    Load-Dock $script:current
})

$btnItemAdd.Add_Click({
    Save-Grid
    $d = Current-Dock
    if ($null -eq $d) { return }
    $d.Items.Add([pscustomobject]@{ Name = '新条目'; Icon = ''; Link = '' }) | Out-Null
    Load-Dock $script:current
    Update-DockList
    $last = $grid.Rows.Count - 1
    if ($last -ge 0) {
        $grid.ClearSelection()
        $grid.Rows[$last].Selected = $true
        $grid.CurrentCell = $grid.Rows[$last].Cells[1]
        try { [void]$grid.BeginEdit($true) } catch { }
        $grid.CurrentCell.Selected = $true
    }
})

$btnItemDel.Add_Click({
    $i = Selected-Row
    if ($i -lt 0) { return }
    Save-Grid
    $d = Current-Dock
    $d.Items.RemoveAt($i)
    Load-Dock $script:current
    Update-DockList
    if ($i -lt $grid.Rows.Count) { $grid.CurrentCell = $grid.Rows[$i].Cells[1] }
})

$btnItemUp.Add_Click({
    $i = Selected-Row
    if ($i -le 0) { return }
    Save-Grid
    Move-GridItem $i ($i - 1)
})

$btnItemDown.Add_Click({
    $i = Selected-Row
    $d = Current-Dock
    if ($i -lt 0 -or $null -eq $d -or $i -ge ($d.Items.Count - 1)) { return }
    Save-Grid
    Move-GridItem $i ($i + 1)
})

$btnItemTop.Add_Click({
    $i = Selected-Row
    if ($i -le 0) { return }
    Save-Grid
    Move-GridItem $i 0 -Shift
})

$btnItemBot.Add_Click({
    $i = Selected-Row
    $d = Current-Dock
    if ($i -lt 0 -or $null -eq $d -or $i -ge ($d.Items.Count - 1)) { return }
    Save-Grid
    Move-GridItem $i ($d.Items.Count - 1) -Shift
})

$btnSetIcon.Add_Click({
    $i = Selected-Row
    if ($i -lt 0) { return }
    Save-Grid
    $f = Pick-File '选择图标' '图片文件 (*.png;*.ico;*.jpg;*.jpeg;*.bmp;*.gif)|*.png;*.ico;*.jpg;*.jpeg;*.bmp;*.gif|所有文件 (*.*)|*.*' $iconRootAbs
    if ($null -eq $f) { return }
    $rel = Resolve-Icon $f
    Set-Cell $i 2 $rel
    Save-Grid
    Set-Status "图标 -> $rel" 'black'
})

$btnSetLink.Add_Click({
    $i = Selected-Row
    if ($i -lt 0) { return }
    Save-Grid
    $f = Pick-File '选择快捷方式 / 程序 / 文件夹目标' '快捷方式 (*.lnk;*.url)|*.lnk;*.url|所有文件 (*.*)|*.*' $linkRootAbs
    if ($null -eq $f) { return }
    $rel = Resolve-Link $f
    Set-Cell $i 3 $rel
    Save-Grid
    Set-Status "链接 -> $rel" 'black'
})

$btnSave.Add_Click({
    Save-Grid
    $errs = @()
    if ($script:docks.Count -eq 0) { $errs += '至少要有一个 Dock。' }
    foreach ($d in $script:docks.Values) {
        if ($d.Name -notmatch '^[A-Za-z0-9_-]+$') { $errs += "Dock 名「$($d.Name)」含非法字符。" }
        if ($d.Items.Count -eq 0) { $errs += "[$($d.Name)] 没有任何条目。" }
        $i = 0
        foreach ($it in $d.Items) {
            $i++
            if ($it.Name -eq '') { $errs += "[$($d.Name)] 第 $i 项标签为空。" }
            if ($it.Icon -eq '') { $errs += "[$($d.Name)] 第 $i 项没有图标。" }
            if ($it.Link -eq '') { $errs += "[$($d.Name)] 第 $i 项没有链接。" }
        }
    }
    if ($errs.Count -gt 0) {
        $show = $errs
        if ($errs.Count -gt 15) { $show = ($errs[0..14] + ('...共 {0} 个问题' -f $errs.Count)) }
        Set-Status ('校验未通过：' + ($show -join ' ')) 'red'
        return
    }

    $savedNames = $script:savedNames
    $removed = @($savedNames | Where-Object { -not $script:docks.Contains($_) })
    $added   = @($script:docks.Keys | Where-Object { $savedNames -notcontains $_ })

    try {
        if (Test-Path $layoutPath) { Copy-Item $layoutPath ($layoutPath + '.bak') -Force }
        Write-Layout

        # 直接用内存模型渲染，不再起子进程、不再重读刚写下的 layout.ini。
        # Variables.inc 每次重读，改样式常量后无需重启编辑器。
        $res = Render-Skins -Docks $script:docks -Vars (Read-SdockVars $varsPath) -Cfg $globalCfg -BasePath $skinBasePath
        $script:savedNames = @($script:docks.Keys)

        $log = ''
        if ($rainExe) {
            foreach ($n in $removed) {
                Start-Process -FilePath $rainExe -ArgumentList '!DeactivateConfig', "sdock\$n" -WindowStyle Hidden
                $log += "卸载 $n "
            }
            if ($removed.Count -gt 0) { Start-Sleep -Milliseconds 400 }
        }
        foreach ($n in $removed) {
            $dir = Join-Path $skinBasePath $n
            $ini = Join-Path $dir ($n + '.ini')
            try {
                if (Test-Path $ini) { Remove-Item $ini -Force }
                if ((Test-Path $dir) -and (@(Get-ChildItem $dir -Force).Count -eq 0)) { Remove-Item $dir -Force }
                $log += "删除 $n\${n}.ini "
            } catch {
                $log += "$n 的文件夹删不掉（可能被占用），请手动删除 $dir "
            }
        }
        if ($rainExe) {
            if ($added.Count -gt 0) {
                # Rainmeter 只在启动时扫描 Skins 目录，外部新建的皮肤文件夹不在它的清单里，
                # 直接 !ActivateConfig 会回 "exists, but is not available. Please refresh Rainmeter."
                # !RefreshApp 会让它重扫一遍，之后新建的 Dock 才加载得进来。
                Start-Process -FilePath $rainExe -ArgumentList '!RefreshApp' -WindowStyle Hidden
                Start-Sleep -Milliseconds 1200
                $log += '重扫皮肤 '
            }
            foreach ($d in $script:docks.Values) {
                if ($savedNames -contains $d.Name) {
                    Start-Process -FilePath $rainExe -ArgumentList '!Refresh', "sdock\$($d.Name)" -WindowStyle Hidden
                } else {
                    Start-Process -FilePath $rainExe -ArgumentList '!ActivateConfig', "sdock\$($d.Name)", "$($d.Name).ini" -WindowStyle Hidden
                    $log += "新加载 $($d.Name) "
                }
            }
            $log += '已刷新皮肤'
        } else {
            $log += '已渲染，但没找到 Rainmeter.exe，请手动刷新皮肤。'
        }

        $tailLines = @($res | ForEach-Object {
            if ($_.Skipped) { return "[SKIP] $($_.Dock)（无条目）" }
            '[OK] {0}.ini {1} 项 {2} 列 背景 {3}x{4} / {5}x{6}' -f $_.Dock, $_.Items, $_.Columns, $_.BgW, $_.BgH, $_.BgW48, $_.BgH48
        })
        $summary = ('保存成功：{0} 个 Dock，{1} 个条目。' -f $script:docks.Count,
                    (@($script:docks.Values | ForEach-Object { $_.Items.Count } | Measure-Object -Sum).Sum))
        Set-Status ($summary + "`r`n" + ($tailLines -join '  ') + "`r`n" + $log) 'green'
        Update-DockList
    } catch {
        Set-Status ('保存失败：' + $_.Exception.Message) 'red'
    }
})

# ------------------------------------------------------------
# boot
# ------------------------------------------------------------
Read-Layout
$iconRootAbs = Expand-Root $globalCfg['IconRoot']
$linkRootAbs = Expand-Root $globalCfg['LinkRoot']
Update-DockList
if ($script:docks.Count -gt 0) { Load-Dock 0 }
Set-Status ("已载入 " + $layoutPath) 'black'
[void]$form.ShowDialog()
