# Omarchy Window Switcher

简体中文 | [English](README.md)

https://github.com/user-attachments/assets/9a04ea39-e196-45a8-99f9-1de1ed632013

一个无需配置的 Omarchy Quattro 插件，结合 Orbit 的可视化窗口切换与 Overview Workspaces 的实时工作区预览。

## 快捷键

| 快捷键 | 单显示器 | 多显示器 |
| --- | --- | --- |
| `Alt+Tab` | 在当前工作区的窗口间切换。 | 在焦点显示器所有普通工作区的窗口间切换。 |
| `Alt+Shift+Tab` | 在同一组窗口中反向切换。 | 在同一组窗口中反向切换。 |
| `Super+Tab` | 在该显示器的工作区间切换。 | 在焦点显示器上以一个网格切换所有显示器的工作区。 |
| `Super+Shift+Tab` | 反向切换工作区。 | 在所有显示器的工作区间反向切换。 |

按住 `Alt` 或 `Super`，连续按 `Tab` 选择，然后松开修饰键，即可激活选中的窗口或工作区。`Super+Tab` 会将已有窗口的工作区排在前面；当前和上一个工作区如果有窗口，会获得优先顺序。空工作区随后列出；“新建工作区”位置不参与循环切换。

## 功能

- 实时工作区缩略图、工作区之间拖放，以及 Overview Workspaces 状态栏组件。
- 保留系统原生的 `Super+1` 到 `Super+0` 工作区快捷键。
- 单独按下再松开 `Super` 不会打开总览。

无需修改 `~/.config/hypr/bindings.lua` 或 `~/.config/omarchy/shell.json`。

## 安装

```bash
omarchy plugin add https://github.com/manateelazycat/omarchy-window-switcher.git --enable --yes
```

插件启用期间会替换 Omarchy 内置的工作区状态栏组件。快捷键在运行时注册，并在 Hyprland 配置重新加载后重新安装。

如果已单独安装 Orbit 或 Overview Workspaces，请先禁用或卸载相应副本，避免两个插件争用相同的全局快捷键和工作区组件。

## 更新

```bash
omarchy plugin update io.github.manateelazycat.window-switcher
omarchy restart shell
```

重启 Shell 会将插件中通过 `keepLoaded` 保留的快捷键服务替换为更新版本。

## 卸载

```bash
omarchy plugin remove io.github.manateelazycat.window-switcher
```

禁用或卸载插件后，Omarchy 原生的 `Alt+Tab`、`Alt+Shift+Tab`、`Super+Tab` 和 `Super+Shift+Tab` 行为会恢复。

## 开发

```bash
omarchy plugin validate .
node --test tests/*.test.cjs
qmllint -I "${OMARCHY_PATH:-/usr/share/omarchy}/shell" \
  orbit/Overlay.qml overview/Overview.qml \
  overview/KeybindingService.qml overview/bar/widget.qml
```

开发时插件文件会热重载。由于快捷键服务使用 `keepLoaded`，修改其代码后需要重启 Omarchy Shell：

```bash
omarchy restart shell
```

## 致谢

本项目得益于两个优秀的上游项目：

- Rohan Patnaik 的 [Orbit](https://github.com/rohan-patnaik/orbit) 提供可视化 `Alt+Tab` 窗口切换器、实时预览和交互设计。
- HANCORE 的 [Overview Workspaces](https://github.com/iamcheyan/omarchy-overview-workspaces) 提供实时工作区预览、导航、拖放和工作区状态栏组件。

两个项目均按 MIT 协议发布。其原始许可证文本和固定的源代码修订版本记录保存在 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。

## 协议

MIT。详见 [LICENSE](LICENSE) 和 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。
