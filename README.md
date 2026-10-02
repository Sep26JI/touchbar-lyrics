# Touch Bar Lyrics · QQ 音乐常驻歌词

独立 macOS 菜单栏应用，让 QQ 音乐在后台播放时仍能在 Touch Bar 上显示歌词，无需 BetterTouchTool。当前版本 **4.4**，在 **M1 MacBook Pro A2338 / macOS 27.0.1** 上开发与验证。

## 功能

- 简洁、胶囊、双行三种风格；可调整字体、字号、文字颜色、强调色。
- 以整条 Touch Bar 为基准居中，可用“水平位置”实时微调。
- 整句进度染色、切句向上滑动、长句平滑滚动。
- 时间进度、上一首、播放／暂停、下一首；进度线目前只读。
- 间奏保留上一句，下一句开始时再切换；长间隔染色默认最多 8 秒完成，可调为 2–15 秒。
- 歌词时间偏移、桌面悬浮歌词、登录启动、本地 UTF-8 LRC 导入。
- QQ 音乐／网易云／LRCLIB 在线歌词及本地缓存。

染色是基于整句时间的视觉估算。普通 LRC 只有每句开始时间，无法保证与每个字或长音精准对应。

## 构建与运行

需要 macOS、Xcode Command Line Tools（Swift 编译器）和 `/usr/bin/python3`。仓库内带 `media-control 0.7.7` 的 ARM64 运行依赖。

```sh
./build.sh
open dist/TouchBarLyrics.app
```

如需登录时启动，先把生成的 app 放入“应用程序”文件夹，再在设置中勾选登录启动。机器缺少 Python 时需要先安装 Command Line Tools。

点击菜单栏音符 → **外观与歌词设置**。使用“收起 Touch Bar 歌词”恢复系统／其他应用内容，再用“显示 Touch Bar 歌词”恢复。

## 适用范围

- 本仓库当前是 ARM64 本机自用构建，未做公证或 Intel 发行验证。
- Touch Bar 物理宽度按 A2338 的 1004 pt 配置；其他机型需核对 `Sources/App.swift` 中 `physicalBarWidth`。
- 系统模态 Touch Bar 使用私有接口，系统升级后可能需要维护。
- 浏览器或其他程序抢占系统正在播放会话时，应用等待 QQ 音乐重新成为当前播放器。
- 暂停、恢复、切换应用已做实机检查；长期运行、锁屏唤醒及所有全屏场景尚未完整覆盖。

## 项目结构

| 路径 | 用途 |
| --- | --- |
| `Sources/DFR.swift` | Touch Bar 系统接口桥接 |
| `Sources/Model.swift` | 播放时钟、歌词时间轴、查询与设置 |
| `Sources/LyricView.swift` | 居中、染色、滚动、切句动画 |
| `Sources/App.swift` | 菜单栏、Touch Bar、设置与桌面歌词 |
| `Resources/lyrics_engine.py` | 歌词查找、LRC 解析及缓存 |
| `Tests/` | 歌词与播放时钟测试 |
| `vendor/media-control/` | 内置媒体读取依赖与许可 |

## 验证

在项目根目录执行：

```sh
/usr/bin/python3 -m unittest discover -s Tests -v
swiftc -parse-as-library -swift-version 5 Sources/Model.swift Tests/ClockTests.swift -o Tests/clock-tests -framework Cocoa
Tests/clock-tests
swiftc -parse-as-library -swift-version 5 Sources/Model.swift Sources/LyricView.swift Tests/LyricEffectsTests.swift -o Tests/lyric-effects-tests -framework Cocoa
Tests/lyric-effects-tests
```

测试覆盖播放暂停／恢复、旧锚点冻结、seek、歌词版本匹配、空白间奏、重复词行、染色上限和居中坐标。渲染测试生成的 PNG、编译产物、本机备份与用户歌词缓存不上传。

## 数据位置

- 设置：`local.touchbar.lyrics` UserDefaults。
- 导入的歌词：`~/Library/Application Support/TouchBarLyrics/lyrics/`。
- 新歌词缓存：`~/Library/Caches/TouchBarLyrics/lyrics/`。
- 兼容读取旧缓存：`~/Library/Caches/qqmusic-tb-lyrics/`。

## 参考与依赖

研究了 [LyricsX](https://github.com/ddddxxx/LyricsX)、[TouchBarHelper](https://github.com/ddddxxx/TouchBarHelper) 和 [Lyrimuse](https://github.com/Yudaotor/lyrimuse) 的接口与媒体读取思路，应用桥接和界面单独实现。

内置 [media-control](https://github.com/ungive/media-control) **0.7.7**（提交 `3cfd5dcf78e7a619f7a42a3e2f29b06eb41027ea`）及其 [mediaremote-adapter](https://github.com/ungive/mediaremote-adapter)。BSD 3-Clause 许可与声明见 `vendor/media-control/LICENSE`、`vendor/media-control/ADAPTER_LICENSE`。
