# sdock

一个 [Rainmeter](https://www.rainmeter.net/)（雨滴桌面）的 dock 皮肤：把常用软件按分类收进多条悬浮 dock，鼠标靠近逐级放大，配置全部由图形化编辑器完成，不手写 ini。

## 特性

- **多 dock 分类**：每个分类（System / Dev / Project / Docs / Media / Network / Other）是一个独立皮肤，可各自摆放位置、独立显示标题与每行列数。
- **三级缩放动画**：收起 32px → 鼠标进入 dock 48px → 悬停单个图标 56px。
- **图形化配置编辑器**：`@Resources\config.ps1` 是一个 WinForms 界面，增删条目、改名、排序、换图标、换链接、导入外部快捷方式，全部点选完成；点「保存并渲染」自动写回配置、重新生成皮肤并刷新 Rainmeter。
- **资源随皮肤打包**：图标 PNG 与快捷方式副本都存放在皮肤自己的 `@Resources\ico\` 与 `@Resources\link\` 里，换机器、拷贝整个皮肤目录都不会丢链接。

## 目录结构

```
sdock/
├── @Resources/
│   ├── layout.ini      # 内容的唯一来源：各 dock 的标题、列数、条目（标签|图标|链接）
│   ├── Variables.inc   # 样式与布局常量（尺寸、间距、圆角、颜色、字体、动画时长）
│   ├── config.ps1      # WinForms 配置编辑器（唯一需要手动运行的脚本）
│   ├── render.ps1      # 纯函数库：读/写 layout.ini + 渲染皮肤 ini，被 config.ps1 点源
│   ├── ico/            # 图标资源（PNG）
│   └── link/           # 快捷方式资源，按 dock 分类分子目录
├── System/System.ini   # 由 render.ps1 生成，共 7 个，每个分类一个
├── Dev/  Docs/  Media/  Network/  Project/  Other/
└── LICENSE             # GPL-3.0
```

`*.ini` 里除 `layout.ini` 与 `Variables.inc` 之外都是**生成产物**：请改 `layout.ini`（或用编辑器改），不要手改这些皮肤文件，否则下次渲染会被覆盖。

## 安装与使用

1. 把整个 `sdock` 文件夹放进 `%APPDATA%\Rainmeter\Skins\`（或 Rainmeter 安装目录下的 `Skins\`）。
2. 在 Rainmeter 里逐个加载 7 个分类皮肤（`sdock\System\System.ini` 等），需要哪些分类就加载哪些。
3. 运行配置编辑器：

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File "$env:APPDATA\Rainmeter\Skins\sdock\@Resources\config.ps1"
   ```

4. 在编辑器里改完点「保存并渲染」，皮肤会自动重写并刷新。

依赖：Windows + [Rainmeter](https://www.rainmeter.net/) + 系统自带的 PowerShell 5.1（编辑器需要 .NET WinForms，无需额外安装）。

## 关于图标与链接

- 图标和链接**只能引用资源文件夹内**的文件（`ico\`、`link\`）。编辑器会拦截库外引用。
- 想加桌面上的软件：用「**导入快捷方式**」按钮选中 `.lnk`，它会一键把图标提取成 256px PNG 存进 `ico\`、把快捷方式副本按分类存进 `link\`，并自动建好条目。
- **删除条目会真删**它独占的资源文件（被其它条目共用的会自动保留），保存后生效；想留着就不删。

## 关于本仓库里的现成内容

仓库自带的图标和快捷方式来自作者自己的环境，仅作示例。直接删掉 `ico\`、`link\` 和 `layout.ini` 里的条目，再从你自己的软件重新导入即可——分类名、条目顺序、每行列数都可以随意改。

## 许可

GPL-3.0-only，详见 [LICENSE](LICENSE)。
