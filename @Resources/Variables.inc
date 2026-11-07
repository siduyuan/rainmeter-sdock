; ============================================
; sdock - 共享变量配置
; 位置: @Resources/Variables.inc
; ============================================

[Variables]
; === 全局设置 ===
; Rainmeter 更新间隔（ms）：所有计时精度都等于这个值，改小会更跟手但略增开销
Update=200

; 鼠标离开后延迟收缩的等待轮数（实际延迟 ≈ LeaveDelayTicks × Update，且不会超过它）
; 5 × 200ms = 1.0 秒（实测落在 0.8 ~ 1.0 秒）
LeaveDelayTicks=5

; 图标尺寸（三级放大）
IconSize=32
IconDockSize=48
IconHoverSize=56

; 当前尺寸（初始值）
CurrentSize=32

; 间距
IconPadding=8
DockPadding=12
ItemSpacing=4

; 布局（列数和行间距）
Columns=1
RowPadding=10

; 圆角
CornerRadius=8
IconCornerRadius=6

; 颜色
DockBgColor=20,20,30,200
DockBorderColor=60,60,80,150
IconHoverColor=255,255,255,80
TextColor=220,220,220,255
TextHoverColor=255,255,255,255
TitleBarColor=30,30,40,150
IconBgColor=40,40,50,180
OverlayColor=10,10,20,120

; 字体
FontName=Segoe UI
FontSize=10
TitleFontSize=12
LabelFontSize=8

; 动画
HoverAnimationTime=200

; 离开计时器（初始值）
LeaveTimer=0

; 起始Y坐标（标题栏下方）
IconStartY=40

; 标题栏高度
TitleBarHeight=30

; 图标与快捷方式的根路径已移入 @Resources\layout.ini 的 [sdock] 段
; （IconRoot / LinkRoot，现值 #@#ico 与 #@#link，资源随皮肤打包）
