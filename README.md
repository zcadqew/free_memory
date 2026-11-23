FreeMemory · 一键释放内存
Windows 平台的一键释放内存工具。PowerShell 5.1 + Windows Forms 原生 GUI,零第三方依赖。

功能
关闭后台所有非必要进程,仅保留:

显卡驱动相关进程(NVIDIA / AMD / Intel)
壁纸类进程(Wallpaper Engine 等)
Steam 相关进程
同时保护系统关键进程避免崩溃。适用于想快速腾出内存、又不想手动逐个关程序的场景。

运行
双击 内存.bat 即可启动。也可以直接执行:

powershell -ExecutionPolicy Bypass -File ".\FreeMemory.ps1"
执行前请先保存好其它程序里的工作 —— 浏览器/文档等会被关闭。激进模式才会关 explorer(附带"重启桌面"按钮)。

文件
FreeMemory.ps1 — 主程序(UTF-8 BOM 编码,兼容中文机器上的 PowerShell 5.1)
内存.bat — 启动器(UTF-8 codepage)
memory-cleanup-icon.svg / .ico — 应用图标(多尺寸 ICO:16/32/48/256)
gen_icon.py — 纯标准库图标生成器(无 PIL / ImageMagick 依赖)
