# render.ps1 - sdock 渲染库
#
# 本文件只提供函数，由 config.ps1 点源（dot-source）后调用，不单独运行。
#   Read-SdockVars     读 Variables.inc -> 样式常量表
#   Read-SdockLayout   读 layout.ini -> dock 内容模型 + [sdock] 全局配置
#   Write-SdockLayout  dock 内容模型 -> layout.ini
#   Render-Skins       dock 内容模型 -> 每个 Dock 一个皮肤 ini，返回渲染结果数组
#
# 内容（标题/图标/链接/标签）的唯一来源: @Resources\layout.ini
# 样式与布局常量来源: @Resources\Variables.inc
# 三级缩放: 32px(收起) -> 48px(鼠标进入 dock) -> 56px(鼠标悬停单个图标)

function Read-IniLines($path) { [System.IO.File]::ReadAllLines($path) }

# ---------- layout constants from Variables.inc ----------
function Read-SdockVars($path) {
    $V = @{}
    foreach ($l in Read-IniLines $path) {
        if ($l -match '^([A-Za-z0-9_]+)=(.*)$') { $V[$Matches[1]] = $Matches[2] }
    }
    foreach ($need in @("DockPadding","IconSize","IconDockSize","IconHoverSize","IconStartY","ItemSpacing","RowPadding","TitleBarHeight")) {
        if (-not $V.ContainsKey($need)) { throw "Variables.inc 缺少 $need" }
    }
    return $V
}

# ---------- content model from layout.ini ----------
# 返回 [pscustomobject]@{ Docks = [ordered]@{ 名 -> dock }; Global = @{ IconRoot; LinkRoot; ... } }
# dock = [pscustomobject]@{ Name; Title; Columns; Items = List[ { Order; Name; Icon; Link } ] }
# Items 已按 ItemN 的数字序排好，列表顺序就是图标排列顺序。
function Read-SdockLayout($path) {
    $nd  = [ordered]@{}
    $cfg = @{ IconRoot = '#@#ico'; LinkRoot = '#@#link' }
    $cur = $null
    foreach ($line in Read-IniLines $path) {
        if ($line -match '^\s*(;|$)') { continue }
        if ($line -match '^\s*\[([^\]]+)\]\s*$') {
            $name = $Matches[1]
            if ($name -eq 'sdock') { $cur = 'sdock'; continue }
            $cur = $name
            $nd[$name] = [pscustomobject]@{
                Name    = $name
                Title   = $name
                Columns = 3
                Items   = (New-Object System.Collections.Generic.List[object])
            }
            continue
        }
        if ($null -eq $cur) { continue }
        if ($line -notmatch '^\s*([A-Za-z0-9_]+)\s*=\s*(.*)$') { continue }
        $k = $Matches[1]
        $v = $Matches[2].Trim()
        if ($cur -eq 'sdock') { $cfg[$k] = $v; continue }
        $d = $nd[$cur]
        if ($k -eq 'Title') {
            $d.Title = $v
        } elseif ($k -eq 'Columns') {
            $intv = 0
            if ([int]::TryParse($v, [ref]$intv)) { $d.Columns = $intv }
        } elseif ($k -match '^Item(\d+)$') {
            $idx = [int]$Matches[1]
            $p = $v -split '\|', 3
            $lbl = ''; $ico = ''; $tgt = ''
            if ($p.Count -ge 1) { $lbl = $p[0] }
            if ($p.Count -ge 2) { $ico = $p[1] }
            if ($p.Count -ge 3) { $tgt = $p[2] }
            $d.Items.Add([pscustomobject]@{ Order = $idx; Name = $lbl; Icon = $ico; Link = $tgt }) | Out-Null
        }
    }
    foreach ($d in $nd.Values) {
        $sorted = @($d.Items | Sort-Object Order)
        $d.Items.Clear()
        foreach ($it in $sorted) { $d.Items.Add($it) | Out-Null }
    }
    return [pscustomobject]@{ Docks = $nd; Global = $cfg }
}

# ---------- write the content model back to layout.ini ----------
function Write-SdockLayout($path, $Docks, $Cfg) {
    $utf8bom = New-Object System.Text.UTF8Encoding($true)
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('; sdock layout - the ONLY content source; parsed by render.ps1 and the config GUI, never by Rainmeter')
    $lines.Add("; item line: ItemN=Label|IconFile|LinkTarget   ('|' cannot occur in Windows file names)")
    $lines.Add('[sdock]')
    $lines.Add('IconRoot=' + $Cfg['IconRoot'])
    $lines.Add('LinkRoot=' + $Cfg['LinkRoot'])
    foreach ($d in $Docks.Values) {
        $lines.Add('')
        $lines.Add('[' + $d.Name + ']')
        $lines.Add('Title=' + $d.Title)
        $lines.Add('Columns=' + $d.Columns)
        $i = 0
        foreach ($it in $d.Items) {
            $i++
            $lines.Add('Item' + $i + '=' + $it.Name + '|' + $it.Icon + '|' + $it.Link)
        }
    }
    [System.IO.File]::WriteAllText($path, (($lines -join "`r`n") + "`r`n"), $utf8bom)
}

# ---------- emit one skin ini per dock ----------
# 返回结果数组，每项: @{ Dock; Skipped; Items; Columns; BgW; BgH; BgW48; BgH48 }
function Render-Skins {
    param(
        [Parameter(Mandatory)] $Docks,
        [Parameter(Mandatory)] [hashtable] $Vars,
        [Parameter(Mandatory)] [hashtable] $Cfg,
        [Parameter(Mandatory)] [string] $BasePath
    )

    $dockPadding  = [int]$Vars["DockPadding"]
    $iconSize     = [int]$Vars["IconSize"]
    $iconDockSize = [int]$Vars["IconDockSize"]
    $iconHoverSize= [int]$Vars["IconHoverSize"]
    $iconStartY   = [int]$Vars["IconStartY"]
    $itemSpacing  = [int]$Vars["ItemSpacing"]
    $rowPadding   = [int]$Vars["RowPadding"]
    $titleBarH    = [int]$Vars["TitleBarHeight"]
    $V_Update     = [int]$Vars["Update"]
    $labelGap     = 14   # 48px 状态显示标签时多出的行高
    $hOff         = [Math]::Floor(($iconHoverSize - $iconDockSize) / 2)

    $IconRoot = $Cfg["IconRoot"]
    $LinkRoot = $Cfg["LinkRoot"]
    if ([string]::IsNullOrEmpty($IconRoot) -or [string]::IsNullOrEmpty($LinkRoot)) { throw "layout.ini [sdock] 缺少 IconRoot / LinkRoot" }
    $IconRoot = $IconRoot.TrimEnd('\')
    $LinkRoot = $LinkRoot.TrimEnd('\')

    $results = New-Object System.Collections.Generic.List[object]
    $sb = $null
    function AL($s) { [void]$sb.AppendLine($s) }

    foreach ($skinFolder in $Docks.Keys) {
        $d = $Docks[$skinFolder]
        $itemList = $d.Items
        $itemCount = $itemList.Count
        if ($itemCount -eq 0) {
            $results.Add([pscustomobject]@{ Dock=$skinFolder; Skipped=$true; Items=0; Columns=0; BgW=0; BgH=0; BgW48=0; BgH48=0 }) | Out-Null
            continue
        }
        $columns = $d.Columns
        if ($columns -lt 1) { $columns = 1 }
        $dockTitle = $d.Title
        if ([string]::IsNullOrEmpty($dockTitle)) { $dockTitle = $skinFolder }

        $rows = [Math]::Ceiling($itemCount / $columns)
        $bgW   = $dockPadding * 2 + $columns * $iconSize     + ($columns - 1) * $rowPadding
        $bgH   = $iconStartY + $rows * ($iconSize + $itemSpacing) + $dockPadding
        $bgW48 = $dockPadding * 2 + $columns * $iconDockSize + ($columns - 1) * $rowPadding
        $bgH48 = $iconStartY + $rows * ($iconDockSize + $itemSpacing + $labelGap) + $dockPadding

        $sb = New-Object System.Text.StringBuilder

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
            $it = $itemList[$i]
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

        $skinDir = Join-Path $BasePath $skinFolder
        if (-not (Test-Path $skinDir)) { New-Item -ItemType Directory -Path $skinDir -Force | Out-Null }
        [System.IO.File]::WriteAllText((Join-Path $skinDir "$skinFolder.ini"), $sb.ToString(), [System.Text.Encoding]::Unicode)
        $results.Add([pscustomobject]@{ Dock=$skinFolder; Skipped=$false; Items=$itemCount; Columns=$columns; BgW=$bgW; BgH=$bgH; BgW48=$bgW48; BgH48=$bgH48 }) | Out-Null
    }

    return $results.ToArray()
}
