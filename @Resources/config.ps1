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
# 删除条目 / Dock 时排队等待落盘的独占资源文件（保存成功后才真删）。
$script:pendingDel = @()

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

$lblHint = New-Label ("提示：图标 / 链接只能引用资源文件夹（ico\ 与 link\）内的文件。`r`n" + "外部快捷方式请用「导入快捷方式」：自动提取图标入库 + 复制链接入库。`r`n删除条目会连它独占的资源文件一起真删（保存后生效）。") 12 552 258 74
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

$btnItemAdd  = New-Button '添加条目'     290 542 92 28
$btnItemDel  = New-Button '删除条目'     388 542 92 28
$btnImport   = New-Button '导入快捷方式' 486 542 100 28
$btnItemUp   = New-Button '上移'         590 542 52 28
$btnItemDown = New-Button '下移'         646 542 52 28
$btnItemTop  = New-Button '置顶'         702 542 52 28
$btnItemBot  = New-Button '置底'         758 542 52 28
$btnSetIcon  = New-Button '更换图标'     814 542 84 28
$btnSetLink  = New-Button '更换链接'     902 542 84 28
foreach ($b in @($btnItemAdd, $btnItemDel, $btnImport, $btnItemUp, $btnItemDown, $btnItemTop, $btnItemBot, $btnSetIcon, $btnSetLink)) {
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
# 图标与链接只允许引用资源文件夹内的文件，外部的走「导入快捷方式」
# ------------------------------------------------------------
$iconRootAbs = Expand-Root $globalCfg['IconRoot']
$linkRootAbs = Expand-Root $globalCfg['LinkRoot']

function Within-Root([string]$full, [string]$root) {
    $r = $root.TrimEnd('\') + '\'
    return $full.StartsWith($r, [System.StringComparison]::OrdinalIgnoreCase)
}

function Relative-To([string]$full, [string]$root) {
    return $full.Substring($root.TrimEnd('\').Length + 1)
}

function To-Abs([string]$root, [string]$v) {
    if ([System.IO.Path]::IsPathRooted($v)) { return [System.IO.Path]::GetFullPath($v) }
    return [System.IO.Path]::GetFullPath((Join-Path $root $v))
}

# 目录内不重名的目标路径
function Unique-Path([string]$dir, [string]$base, [string]$ext) {
    $dest = Join-Path $dir ($base + $ext)
    $n = 1
    while (Test-Path $dest) {
        $dest = Join-Path $dir ('{0}_{1}{2}' -f $base, $n, $ext)
        $n++
    }
    return $dest
}

function Safe-Name([string]$s) {
    foreach ($ch in [System.IO.Path]::GetInvalidFileNameChars()) { $s = $s.Replace([string]$ch, '_') }
    return $s.Trim()
}

# SHDefExtractIcon / ExtractIconEx 能拿到程序里最大号的图标（ExtractAssociatedIcon 只有 32px）。
# 两段都编译不进（没有 C# 编译器）就退回 ExtractAssociatedIcon。
if (-not ('SdockWin32' -as [type])) {
    try {
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class SdockWin32 {
    [DllImport("shell32.dll", CharSet=CharSet.Unicode)]
    public static extern uint ExtractIconEx(string file, int index, IntPtr[] large, IntPtr[] small, uint count);
    [DllImport("shell32.dll", CharSet=CharSet.Unicode)]
    public static extern int SHDefExtractIcon(string file, int index, uint flags, out IntPtr large, out IntPtr small, uint size);
    [DllImport("user32.dll")]
    public static extern bool DestroyIcon(IntPtr h);
}
'@
    } catch { }
}

# 取 file 的第 $index 个图标存成 PNG；失败返回 $false（不会留下半个文件）
function Save-IconPng([string]$file, [int]$index, [string]$dest) {
    $h = [IntPtr]::Zero
    $owned = $false
    if ('SdockWin32' -as [type]) {
        # 先要 256px 的（现代程序一般给得出），拿不到再退回 ExtractIconEx 的最大号图标。
        try {
            $big = [IntPtr]::Zero
            $sml = [IntPtr]::Zero
            if (([SdockWin32]::SHDefExtractIcon($file, $index, 0, [ref]$big, [ref]$sml, 256) -eq 0) -and $big -ne [IntPtr]::Zero) {
                $h = $big; $owned = $true
                if ($sml -ne [IntPtr]::Zero) { [void][SdockWin32]::DestroyIcon($sml) }
            }
        } catch { }
        if ($h -eq [IntPtr]::Zero) {
            try {
                $lg = [IntPtr[]]::New(1)
                $sm = [IntPtr[]]::New(1)
                $n = [SdockWin32]::ExtractIconEx($file, $index, $lg, $sm, 1)
                if ($n -gt 0 -and $lg[0] -ne [IntPtr]::Zero) { $h = $lg[0]; $owned = $true }
                elseif ($n -gt 0 -and $sm[0] -ne [IntPtr]::Zero) { $h = $sm[0]; $owned = $true }
            } catch { }
        }
    }
    $bmp = $null
    $tmp = $dest + '.tmp'
    try {
        if ($h -ne [IntPtr]::Zero) {
            $ico = [System.Drawing.Icon]::FromHandle($h)
            $bmp = $ico.ToBitmap()
        } else {
            $ico = [System.Drawing.Icon]::ExtractAssociatedIcon($file)
            if ($null -eq $ico) { return $false }
            $bmp = $ico.ToBitmap()
        }
        $bmp.Save($tmp, [System.Drawing.Imaging.ImageFormat]::Png)
        Move-Item $tmp $dest -Force
        return $true
    } catch {
        if (Test-Path $tmp) { Remove-Item $tmp -Force }
        return $false
    } finally {
        if ($bmp) { $bmp.Dispose() }
        if ($owned -and ('SdockWin32' -as [type])) { [void][SdockWin32]::DestroyIcon($h) }
    }
}

# .lnk 的目标程序与自定义图标位置；读不出来返回 $null
function Shortcut-Info([string]$lnk) {
    try {
        $sh = New-Object -ComObject WScript.Shell
        $sl = $sh.CreateShortcut($lnk)
        $r = @{ Target = [string]$sl.TargetPath; IconFile = ''; IconIndex = 0 }
        $il = [string]$sl.IconLocation
        if ($il) {
            $parts = $il -split ','
            $r.IconFile = $parts[0].Trim().Trim('"')
            if ($parts.Count -gt 1) {
                $ix = 0
                if ([int]::TryParse($parts[1].Trim(), [ref]$ix)) { $r.IconIndex = $ix }
            }
        }
        [void][System.Runtime.InteropServices.Marshal]::ReleaseComObject($sh)
        return $r
    } catch { return $null }
}

# 外部快捷方式入库：link\<分类>\x.lnk + ico\x.png，返回相对路径
function Import-Shortcut([string]$src, [string]$category) {
    $full = [System.IO.Path]::GetFullPath($src)
    if (-not (Test-Path $full)) { return @{ Error = '文件不存在' } }
    $ext = [System.IO.Path]::GetExtension($full).ToLower()
    if (($ext -ne '.lnk') -and ($ext -ne '.url')) { return @{ Error = '不是快捷方式（只支持 .lnk / .url）' } }
    $base = Safe-Name ([System.IO.Path]::GetFileNameWithoutExtension($full))
    if ($base -eq '') { return @{ Error = '快捷方式名无效' } }

    $linkRel = ''
    if (Within-Root $full $linkRootAbs) {
        $linkRel = Relative-To $full $linkRootAbs
    } else {
        $dir = Join-Path $linkRootAbs (Safe-Name $category)
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        $dest = Unique-Path $dir $base $ext
        try { Copy-Item -LiteralPath $full -Destination $dest -Force }
        catch { return @{ Error = ('快捷方式复制失败：' + $_.Exception.Message) } }
        $linkRel = Relative-To $dest $linkRootAbs
    }

    if (-not (Test-Path $iconRootAbs)) { New-Item -ItemType Directory -Path $iconRootAbs -Force | Out-Null }
    $icoRel = ''; $warn = ''
    # 图标来源优先级：快捷方式自定义图标位置 -> 目标程序 -> 快捷方式本身
    $candFile = New-Object System.Collections.Generic.List[string]
    $candIndex = New-Object System.Collections.Generic.List[int]
    if ($ext -eq '.lnk') {
        $info = Shortcut-Info $full
        if ($info) {
            $ifile = $info.IconFile
            if ($ifile) {
                $ifile = [Environment]::ExpandEnvironmentVariables($ifile)
                if (-not [System.IO.Path]::IsPathRooted($ifile)) {
                    $ifile = Join-Path ([System.IO.Path]::GetDirectoryName($full)) $ifile
                }
                if (Test-Path $ifile) {
                    $candFile.Add($ifile) | Out-Null
                    $candIndex.Add([int]$info.IconIndex) | Out-Null
                }
            }
            if ($info.Target -and (Test-Path $info.Target)) {
                $candFile.Add($info.Target) | Out-Null
                $candIndex.Add(0) | Out-Null
            }
        }
    }
    $candFile.Add($full) | Out-Null
    $candIndex.Add(0) | Out-Null
    $icoDest = Unique-Path $iconRootAbs $base '.png'
    for ($t = 0; $t -lt $candFile.Count; $t++) {
        if (Save-IconPng $candFile[$t] $candIndex[$t] $icoDest) { $icoRel = [System.IO.Path]::GetFileName($icoDest); break }
    }
    if ($icoRel -eq '') { $warn = '没能从快捷方式提取到图标，请用「更换图标」从 ico\ 里补一个' }

    return @{ Name = $base; Link = $linkRel; Icon = $icoRel; Warn = $warn }
}

# 条目引用、且位于资源文件夹内的文件 -> 绝对路径列表
function Resource-Files($it) {
    $out = @()
    if ($it.Icon) {
        $a = To-Abs $iconRootAbs $it.Icon
        if ((Within-Root $a $iconRootAbs) -and (Test-Path $a)) { $out += $a }
    }
    if ($it.Link) {
        $a = To-Abs $linkRootAbs $it.Link
        if ((Within-Root $a $linkRootAbs) -and (Test-Path $a)) { $out += $a }
    }
    return $out
}

function Resolve-Icon([string]$picked) {
    $full = [System.IO.Path]::GetFullPath($picked)
    if (Within-Root $full $iconRootAbs) { return Relative-To $full $iconRootAbs }
    return $null
}

function Resolve-Link([string]$picked) {
    $full = [System.IO.Path]::GetFullPath($picked)
    if (Within-Root $full $linkRootAbs) { return Relative-To $full $linkRootAbs }
    return $null
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
    $files = @()
    foreach ($it in $d.Items) { $files += Resource-Files $it }
    $fileMsg = '该 Dock 的条目没有引用 ico\ / link\ 内的文件。'
    if ($files.Count -gt 0) {
        $shown = $files
        if ($files.Count -gt 6) { $shown = ($files[0..5] + ('...共 {0} 个文件' -f $files.Count)) }
        $fileMsg = "保存后会一并删除它独占的 $($files.Count) 个资源文件：`r`n" + (($shown | ForEach-Object { [System.IO.Path]::GetFileName($_) }) -join "`r`n")
    }
    $res = [System.Windows.Forms.MessageBox]::Show(
        "确定删除 Dock「$($d.Name)」及其 $($d.Items.Count) 个条目吗？`r`n保存后会卸载该皮肤，并删除皮肤文件 $($d.Name)\$($d.Name).ini（文件夹空了也一并删掉）。`r`n" + $fileMsg + "`r`nlayout.ini 会先备份。",
        'sdock', 'YesNo', 'Warning')
    if ($res -ne [System.Windows.Forms.DialogResult]::Yes) { return }
    foreach ($f in $files) { $script:pendingDel += $f }
    $arr = @($script:docks.Values | Where-Object { $_.Name -ne $d.Name })
    Rebuild-Docks $arr
    if ($script:current -ge $arr.Count) { $script:current = $arr.Count - 1 }
    Update-DockList
    if ($arr.Count -gt 0) { Load-Dock $script:current } else {
        $grid.Rows.Clear()
        $lblItems.Text = '条目数：0'
    }
    Set-Status "已删除 Dock，排队待删 $($files.Count) 个资源文件，点「保存并渲染」后生效。" 'black'
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
    $it = $d.Items[$i]
    $files = Resource-Files $it
    $msg = "确定删除条目「$($it.Name)」吗？"
    if ($files.Count -gt 0) {
        $msg += "`r`n`r`n保存后会一并删除资源文件：`r`n" + ($files -join "`r`n") + "`r`n（被其它条目共用的会自动保留）"
    } else {
        $msg += "`r`n`r`n这个条目没有引用 ico\ / link\ 内的文件，只从 layout.ini 移除。"
    }
    $res = [System.Windows.Forms.MessageBox]::Show($msg, 'sdock', 'YesNo', 'Question')
    if ($res -ne [System.Windows.Forms.DialogResult]::Yes) { return }
    foreach ($f in $files) { $script:pendingDel += $f }
    $d.Items.RemoveAt($i)
    Load-Dock $script:current
    Update-DockList
    if ($i -lt $grid.Rows.Count) { $grid.CurrentCell = $grid.Rows[$i].Cells[1] }
    if ($files.Count -gt 0) { Set-Status "已删除条目，待删 $($files.Count) 个资源文件，点「保存并渲染」后生效。" 'black' }
})

$btnImport.Add_Click({
    $d = Current-Dock
    if ($null -eq $d) { return }
    Save-Grid
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Title = '导入外部快捷方式（可多选）'
    $dlg.Filter = '快捷方式 (*.lnk;*.url)|*.lnk;*.url|所有文件 (*.*)|*.*'
    $dlg.Multiselect = $true
    $desk = [Environment]::GetFolderPath('Desktop')
    if ($desk -and (Test-Path $desk)) { $dlg.InitialDirectory = $desk }
    if ($dlg.ShowDialog($form) -ne [System.Windows.Forms.DialogResult]::OK) { return }
    $cat = if ($d.Title) { $d.Title } else { $d.Name }
    $ok = 0; $msgs = @()
    foreach ($f in $dlg.FileNames) {
        $full = [System.IO.Path]::GetFullPath($f)
        if ((Within-Root $full $linkRootAbs) -or (Within-Root $full $iconRootAbs)) {
            $msgs += ('已在资源库内，请改用「更换图标 / 更换链接」：' + [System.IO.Path]::GetFileName($full))
            continue
        }
        $r = Import-Shortcut $full $cat
        if ($r.Error) { $msgs += ('失败 ' + [System.IO.Path]::GetFileName($full) + '：' + $r.Error); continue }
        $d.Items.Add([pscustomobject]@{ Name = $r.Name; Icon = $r.Icon; Link = $r.Link }) | Out-Null
        $ok++
        if ($r.Warn) { $msgs += ($r.Name + '：' + $r.Warn) }
    }
    Load-Dock $script:current
    Update-DockList
    $last = $grid.Rows.Count - 1
    if ($ok -gt 0 -and $last -ge 0) {
        $grid.ClearSelection()
        $grid.Rows[$last].Selected = $true
        $grid.CurrentCell = $grid.Rows[$last].Cells[1]
    }
    $log = "已导入 $ok 个到 [$($d.Name)]，图标 / 链接已入库，点「保存并渲染」上屏。"
    if ($msgs.Count -gt 0) { $log += "`r`n" + (($msgs | Select-Object -First 8) -join "`r`n") }
    Set-Status $log $(if ($ok -gt 0) { 'green' } else { 'red' })
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
    $f = Pick-File '选择图标（只能用 ico\ 内的文件）' '图片文件 (*.png;*.ico;*.jpg;*.jpeg;*.bmp;*.gif)|*.png;*.ico;*.jpg;*.jpeg;*.bmp;*.gif|所有文件 (*.*)|*.*' $iconRootAbs
    if ($null -eq $f) { return }
    $rel = Resolve-Icon $f
    if ($null -eq $rel) {
        [void][System.Windows.Forms.MessageBox]::Show(
            '图标只能引用资源文件夹 ico\ 内的文件。' + "`r`n" + '选中的文件在它之外：' + $f + "`r`n`r`n" + '如果这是某个程序的快捷方式，请用「导入快捷方式」，它会自动把图标提取到 ico\ 入库。',
            'sdock 配置编辑器', 'OK', 'Warning')
        Set-Status '图标未修改：所选文件在 ico\ 之外' 'red'
        return
    }
    Set-Cell $i 2 $rel
    Save-Grid
    Set-Status "图标 -> $rel" 'black'
})

$btnSetLink.Add_Click({
    $i = Selected-Row
    if ($i -lt 0) { return }
    Save-Grid
    $f = Pick-File '选择快捷方式（只能用 link\ 内的文件）' '快捷方式 (*.lnk;*.url)|*.lnk;*.url|所有文件 (*.*)|*.*' $linkRootAbs
    if ($null -eq $f) { return }
    $rel = Resolve-Link $f
    if ($null -eq $rel) {
        [void][System.Windows.Forms.MessageBox]::Show(
            '链接只能引用资源文件夹 link\ 内的快捷方式。' + "`r`n" + '选中的文件在它之外：' + $f + "`r`n`r`n" + '请用「导入快捷方式」，它会把快捷方式复制到 link\分类\ 入库（.lnk 还会顺便提取图标）。',
            'sdock 配置编辑器', 'OK', 'Warning')
        Set-Status '链接未修改：所选文件在 link\ 之外' 'red'
        return
    }
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
            if ($it.Icon -ne '') {
                $ia = To-Abs $iconRootAbs $it.Icon
                if (-not (Within-Root $ia $iconRootAbs)) { $errs += "[$($d.Name)] 第 $i 项图标在 ico\ 之外，请用「导入快捷方式」。" }
                elseif (-not (Test-Path $ia)) { $errs += "[$($d.Name)] 第 $i 项图标文件不存在：ico\$($it.Icon)。" }
            }
            if ($it.Link -ne '') {
                $la = To-Abs $linkRootAbs $it.Link
                if (-not (Within-Root $la $linkRootAbs)) { $errs += "[$($d.Name)] 第 $i 项链接在 link\ 之外，请用「导入快捷方式」。" }
                elseif (-not (Test-Path $la)) { $errs += "[$($d.Name)] 第 $i 项快捷方式不存在：link\$($it.Link)。" }
            }
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

        # 真正的删除：条目 / Dock 移除后，把只属于它们的资源文件从磁盘清掉。
        # 仍被其它条目引用的自动保留（PowerShell 哈希表大小写不敏感，路径共用也能识别）。
        if ($script:pendingDel.Count -gt 0) {
            $referenced = @{}
            foreach ($dd in $script:docks.Values) {
                foreach ($it in $dd.Items) {
                    if ($it.Icon) { $referenced[(To-Abs $iconRootAbs $it.Icon)] = $true }
                    if ($it.Link) { $referenced[(To-Abs $linkRootAbs $it.Link)] = $true }
                }
            }
            $delOk = 0; $delKeep = 0; $delFail = @()
            foreach ($fp in ($script:pendingDel | Select-Object -Unique)) {
                if ($referenced.ContainsKey($fp)) { $delKeep++; continue }
                if (-not (Test-Path -LiteralPath $fp)) { continue }
                try { Remove-Item -LiteralPath $fp -Force; $delOk++ } catch { $delFail += $fp }
            }
            $log += "删除资源文件 $delOk 个"
            if ($delKeep -gt 0) { $log += "（$delKeep 个被别的条目共用，保留）" }
            if ($delFail.Count -gt 0) { $log += ('；被占用删不掉，请手动删除：' + ($delFail -join '；')) }
            if (Test-Path -LiteralPath $linkRootAbs) {
                foreach ($sub in @(Get-ChildItem -LiteralPath $linkRootAbs -Directory -Force)) {
                    if (@(Get-ChildItem -LiteralPath $sub.FullName -Recurse -File -Force).Count -eq 0) {
                        try { Remove-Item -LiteralPath $sub.FullName -Recurse -Force; $log += "清空分类文件夹 $($sub.Name) " } catch { }
                    }
                }
            }
            $script:pendingDel = @()
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
