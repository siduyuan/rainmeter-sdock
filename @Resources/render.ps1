# render.ps1 - sdock 皮肤渲染器
#
# 内容（标题/图标/链接/标签）的唯一来源: @Resources\layout.ini
# 样式与布局常量来源: @Resources\Variables.inc
#
# 本脚本从 layout.ini 渲染出 7 个皮肤 ini。改完 layout.ini 后重跑本脚本，
# 再在 Rainmeter 里刷新皮肤即可。样式常量暂时仍手改 Variables.inc。
# 三级缩放: 32px(收起) -> 48px(鼠标进入 dock) -> 56px(鼠标悬停单个图标)

$ErrorActionPreference = "Stop"

$resourcesDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$skinBasePath = Split-Path -Parent $resourcesDir
$layoutPath   = Join-Path $resourcesDir "layout.ini"

function Read-IniLines($path) { [System.IO.File]::ReadAllLines($path) }

# ---------- 1. layout constants from Variables.inc ----------
$V = @{}
foreach ($l in Read-IniLines (Join-Path $resourcesDir "Variables.inc")) {
    if ($l -match '^([A-Za-z0-9_]+)=(.*)$') { $V[$Matches[1]] = $Matches[2] }
}
foreach ($need in @("DockPadding","IconSize","IconDockSize","IconHoverSize","IconStartY","ItemSpacing","RowPadding","TitleBarHeight")) {
    if (-not $V.ContainsKey($need)) { throw "Variables.inc 缺少 $need" }
}
$dockPadding  = [int]$V["DockPadding"]
$iconSize     = [int]$V["IconSize"]
$iconDockSize = [int]$V["IconDockSize"]
$iconHoverSize= [int]$V["IconHoverSize"]
$iconStartY   = [int]$V["IconStartY"]
$itemSpacing  = [int]$V["ItemSpacing"]
$rowPadding   = [int]$V["RowPadding"]
$titleBarH    = [int]$V["TitleBarHeight"]
$V_Update     = [int]$V["Update"]
$labelGap     = 14   # 48px 状态显示标签时多出的行高
$hOff         = [Math]::Floor(($iconHoverSize - $iconDockSize) / 2)

# ---------- 2. content from layout.ini ----------
$layout = [ordered]@{ }
$global = [ordered]@{}
$cur = $null
foreach ($line in Read-IniLines $layoutPath) {
    if ($line -match '^\s*$' -or $line -match '^\s*;') { continue }
    if ($line -match '^\s*\[([^\]]+)\]\s*$') {
        $name = $Matches[1]
        if ($name -eq 'sdock') { $cur = 'sdock'; continue }
        $cur = $name; $layout[$cur] = [ordered]@{ Title=''; Columns=3; Items=(New-Object System.Collections.Specialized.OrderedDictionary) }
        continue
    }
    if ($cur -eq $null -or $line -notmatch '^\s*([A-Za-z0-9_]+)\s*=\s*(.*)$') { continue }
    $key,$val = $Matches[1],$Matches[2]
    if ($cur -eq 'sdock') { $global[$key]=$val; continue }
    switch -Regex ($key) {
        '^Title$'   { $layout[$cur].Title=$val; break }
        '^Columns$' { $layout[$cur].Columns=[int]$val; break }
        '^Item(\d+)$' {
            $p = $val -split '\|',3
            if ($p.Count -ne 3) { throw "layout.ini [$cur] $key : expected Label|Icon|Target" }
            $layout[$cur].Items[$Matches[1]] = @{ Name=$p[0]; Icon=$p[1]; Link=$p[2] }
            break }
    }
}

$IconRoot = $global["IconRoot"]
$LinkRoot = $global["LinkRoot"]
if ([string]::IsNullOrEmpty($IconRoot) -or [string]::IsNullOrEmpty($LinkRoot)) { throw "layout.ini [sdock] 缺少 IconRoot / LinkRoot" }
$IconRoot = $IconRoot.TrimEnd('\')
$LinkRoot = $LinkRoot.TrimEnd('\')

# items 按 ItemN 的数字序重排，保证键顺序就是图标排列顺序
$docksCfg = [ordered]@{}
foreach ($d in @($layout.Keys)) {
    $cfg = $layout[$d]
    $od = New-Object System.Collections.Specialized.OrderedDictionary
    foreach ($k in ($cfg.Items.Keys | Sort-Object { [int]$_ })) { $od[$k] = $cfg.Items[$k] }
    $cfg.Items = $od
    $docksCfg[$d] = $cfg
}

# ---------- 3. emit one ini per dock ----------
$utf8bom = New-Object System.Text.UTF8Encoding($true)
foreach ($skinFolder in $docksCfg.Keys) {
    $cfg = $docksCfg[$skinFolder]
    $items = $cfg.Items
    $itemCount = $items.Count
    if ($itemCount -eq 0) { Write-Host "[SKIP] $skinFolder 没有条目" -ForegroundColor Yellow; continue }
    $columns = $cfg.Columns
    if ($columns -lt 1) { $columns = 1 }
    $dockTitle = $cfg.Title
    if ([string]::IsNullOrEmpty($dockTitle)) { $dockTitle = $skinFolder }

    $keys = @($items.Keys)
    $rows = [Math]::Ceiling($itemCount / $columns)
    $bgW   = $dockPadding * 2 + $columns * $iconSize     + ($columns - 1) * $rowPadding
    $bgH   = $iconStartY + $rows * ($iconSize + $itemSpacing) + $dockPadding
    $bgW48 = $dockPadding * 2 + $columns * $iconDockSize + ($columns - 1) * $rowPadding
    $bgH48 = $iconStartY + $rows * ($iconDockSize + $itemSpacing + $labelGap) + $dockPadding

    $sb = New-Object System.Text.StringBuilder
    function AL($s) { [void]$sb.AppendLine($s) }

    AL "; ============================================"
    AL "; sdock - $dockTitle Dock"
    AL "; 3-level zoom: ${iconSize}px -> ${iconDockSize}px -> ${iconHoverSize}px"
    AL "; 本文件由 @Resources\render.ps1 生成，内容源: @Resources\layout.ini"
    AL "; ============================================"
    AL ""
    AL "[Rainmeter]"
    AL "Update=$V_Update"
    AL "DynamicWindowSize=1"
    AL "AccurateText=1"
    AL ""
    AL "[Metadata]"
    AL "Name=sdock-$skinFolder"
    AL "Author=User"
    AL "Information=dock - $dockTitle"
    AL "Version=1.0.0"
    AL "License=GPL v3"
    AL ""
    AL "[Variables]"
    AL "@Include=#@#Variables.inc"
    AL "DockTitle=$dockTitle"
    AL "ItemCount=$itemCount"
    AL "Columns=$columns"
    AL "CurrentSize=$iconSize"
    AL "BackgroundW=$bgW"
    AL "BackgroundH=$bgH"
    AL "LeaveTimer=0"
    AL ""

    # mouse left dock -> shrink to $iconSize
    $deactivateCmd = '[!SetVariable CurrentSize "#IconSize#"][!SetVariable BackgroundW "' + $bgW + '"][!SetVariable BackgroundH "' + $bgH + '"]'
    for ($i = 0; $i -lt $itemCount; $i++) {
        $n = $i + 1
        $x = $dockPadding + ($i % $columns) * ($iconSize + $rowPadding)
        $y = $iconStartY + [Math]::Floor($i / $columns) * ($iconSize + $itemSpacing)
        $deactivateCmd += "[!SetOption Item${n}Icon X `"$x`"][!SetOption Item${n}Icon Y `"$y`"][!SetOption Item${n}Icon W `"#IconSize#`"][!SetOption Item${n}Icon H `"#IconSize#`"]"
        $deactivateCmd += "[!SetOption Item${n}Bg X `"$x`"][!SetOption Item${n}Bg Y `"$y`"][!SetOption Item${n}Bg Shape `"Rectangle 0,0,#IconSize#,#IconSize#,6 | Fill Color #IconBgColor# | StrokeWidth 0`"]"
        $deactivateCmd += "[!SetOption Item${n}Label X `"($x + $iconSize/2)`"][!SetOption Item${n}Label Y `"($y + $iconSize + 2)`"][!SetOption Item${n}Label Hidden `"1`"]"
    }
    $deactivateCmd += '[!Update]'

    # mouse enters dock -> expand to $iconDockSize
    $activateCmd = '[!DisableMeasure MeasureLeaveDelay][!SetVariable LeaveTimer "0"][!SetVariable CurrentSize "#IconDockSize#"][!SetVariable BackgroundW "' + $bgW48 + '"][!SetVariable BackgroundH "' + $bgH48 + '"]'
    for ($i = 0; $i -lt $itemCount; $i++) {
        $n = $i + 1
        $x = $dockPadding + ($i % $columns) * ($iconDockSize + $rowPadding)
        $y = $iconStartY + [Math]::Floor($i / $columns) * ($iconDockSize + $itemSpacing + $labelGap)
        $activateCmd += "[!SetOption Item${n}Icon X `"$x`"][!SetOption Item${n}Icon Y `"$y`"][!SetOption Item${n}Icon W `"#IconDockSize#`"][!SetOption Item${n}Icon H `"#IconDockSize#`"]"
        $activateCmd += "[!SetOption Item${n}Bg X `"$x`"][!SetOption Item${n}Bg Y `"$y`"][!SetOption Item${n}Bg Shape `"Rectangle 0,0,#IconDockSize#,#IconDockSize#,6 | Fill Color #IconBgColor# | StrokeWidth 0`"]"
        $activateCmd += "[!SetOption Item${n}Label X `"($x + $iconDockSize/2)`"][!SetOption Item${n}Label Y `"($y + $iconDockSize + 2)`"][!SetOption Item${n}Label Hidden `"0`"]"
    }
    $activateCmd += '[!Update]'

    AL "[MeasureLeaveDelay]"
    AL "Measure=Calc"
    AL "Formula=1"
    AL "Disabled=1"
    AL "DynamicVariables=1"
    AL "OnUpdateAction=[!SetVariable LeaveTimer `"(#LeaveTimer#+1)`"]"
    AL "IfCondition=(#LeaveTimer# + 1) >= #LeaveDelayTicks#"
    AL "IfTrueAction=$deactivateCmd[!DisableMeasure MeasureLeaveDelay][!SetVariable LeaveTimer `"0`"]"
    AL ""
    AL "[Background]"
    AL "Meter=Shape"
    AL "Shape=Rectangle 0,0,#BackgroundW#,#BackgroundH#,8 | Fill Color #DockBgColor# | StrokeWidth 1 | Stroke Color #DockBorderColor#"
    AL "MouseOverAction=$activateCmd"
    AL "MouseLeaveAction=[!EnableMeasure MeasureLeaveDelay]"
    AL "DynamicVariables=1"
    AL ""
    AL "[TitleBar]"
    AL "Meter=Shape"
    AL "Shape=Rectangle 0,0,#BackgroundW#,$titleBarH | Fill Color #TitleBarColor# | StrokeWidth 0"
    AL "DynamicVariables=1"
    AL ""
    AL "[DockTitleText]"
    AL "Meter=String"
    AL "Text=#DockTitle#"
    AL "FontFace=#FontName#"
    AL "FontSize=#TitleFontSize#"
    AL "FontColor=#TextColor#"
    AL "StringStyle=Bold"
    AL "AntiAlias=1"
    AL "X=10"
    AL "Y=8"
    AL ""

    for ($i = 0; $i -lt $itemCount; $i++) {
        $n = $i + 1
        $it = $items[[string]$n]
        if ($it -eq $null) { $it = $items[$keys[$i]] }
        $ix = $dockPadding + ($i % $columns) * ($iconDockSize + $rowPadding)
        $iy = $iconStartY + [Math]::Floor($i / $columns) * ($iconDockSize + $itemSpacing + $labelGap)
        $hx = $ix - $hOff
        $hy = $iy - $hOff

        $hov = "[!SetOption Item${n}Bg X `"$hx`"][!SetOption Item${n}Bg Y `"$hy`"][!SetOption Item${n}Bg Shape `"Rectangle 0,0,#IconHoverSize#,#IconHoverSize#,6 | Fill Color #IconHoverColor# | StrokeWidth 1 | Stroke Color 255,255,255,220`"]"
        $hov += "[!SetOption Item${n}Icon X `"$hx`"][!SetOption Item${n}Icon Y `"$hy`"][!SetOption Item${n}Icon W `"#IconHoverSize#`"][!SetOption Item${n}Icon H `"#IconHoverSize#`"][!Update]"
        $lvd = "[!SetOption Item${n}Bg X `"$ix`"][!SetOption Item${n}Bg Y `"$iy`"][!SetOption Item${n}Bg Shape `"Rectangle 0,0,#IconDockSize#,#IconDockSize#,6 | Fill Color #IconBgColor# | StrokeWidth 0`"]"
        $lvd += "[!SetOption Item${n}Icon X `"$ix`"][!SetOption Item${n}Icon Y `"$iy`"][!SetOption Item${n}Icon W `"#IconDockSize#`"][!SetOption Item${n}Icon H `"#IconDockSize#`"][!Update]"

        $link = $it.Link
        if (($link -notmatch '^[A-Za-z]:\\') -and ($link -notmatch '^\\\\') -and ($link -notmatch '^[A-Za-z][A-Za-z0-9+.-]*://')) { $link = "$LinkRoot\$link" }
        $icon = $it.Icon
        if ($icon -notmatch '^[A-Za-z]:\\') { $icon = "$IconRoot\$icon" }
        $linkBang = "LeftMouseUpAction=[`"$link`"]"
        $iconLine = "ImageName=$icon"

        AL "; --- Item $n ---"
        AL "[Item${n}Bg]"
        AL "Meter=Shape"
        AL "Shape=Rectangle 0,0,#CurrentSize#,#CurrentSize#,6 | Fill Color #IconBgColor# | StrokeWidth 0"
        AL "X=(#DockPadding# + ($i % #Columns#) * (#CurrentSize# + #RowPadding#))"
        AL "Y=(#IconStartY# + Floor($i / #Columns#) * (#CurrentSize# + #ItemSpacing#))"
        AL "MouseOverAction=$hov"
        AL "MouseLeaveAction=$lvd"
        AL $linkBang
        AL "DynamicVariables=1"
        AL ""
        AL "[Item${n}Icon]"
        AL "Meter=Image"
        AL $iconLine
        AL "X=(#DockPadding# + ($i % #Columns#) * (#CurrentSize# + #RowPadding#))"
        AL "Y=(#IconStartY# + Floor($i / #Columns#) * (#CurrentSize# + #ItemSpacing#))"
        AL "W=#CurrentSize#"
        AL "H=#CurrentSize#"
        AL "PreserveAspectRatio=1"
        AL "AntiAlias=1"
        AL "MouseOverAction=$hov"
        AL "MouseLeaveAction=$lvd"
        AL $linkBang
        AL "DynamicVariables=1"
        AL ""
        AL "[Item${n}Label]"
        AL "Meter=String"
        AL "Text=$($it.Name)"
        AL "FontFace=#FontName#"
        AL "FontSize=#LabelFontSize#"
        AL "FontColor=#TextColor#"
        AL "StringAlign=Center"
        AL "AntiAlias=1"
        AL "X=(#DockPadding# + ($i % #Columns#) * (#CurrentSize# + #RowPadding#) + #CurrentSize#/2)"
        AL "Y=(#IconStartY# + Floor($i / #Columns#) * (#CurrentSize# + #ItemSpacing#) + #CurrentSize# + 2)"
        AL "W=#CurrentSize#"
        AL "ClipString=1"
        AL "Hidden=1"
        AL "DynamicVariables=1"
        AL ""
    }

    $skinDir = Join-Path $skinBasePath $skinFolder
    if (-not (Test-Path $skinDir)) { New-Item -ItemType Directory -Path $skinDir -Force | Out-Null }
    [System.IO.File]::WriteAllText((Join-Path $skinDir "$skinFolder.ini"), $sb.ToString(), [System.Text.Encoding]::Unicode)
    Write-Host "[OK] $skinFolder.ini  $itemCount items, $columns cols, bg ${bgW}x${bgH} / ${bgW48}x${bgH48}" -ForegroundColor Green
}

Write-Host ""
Write-Host "渲染完成。日常改内容只需编辑 $layoutPath 后刷新皮肤。" -ForegroundColor Cyan
