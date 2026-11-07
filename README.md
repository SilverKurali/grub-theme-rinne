# GRUB 主题 · 星空

一个为 Fedora 45（及任何 GRUB 2.12 系统）做的深色 GRUB 主题，附带一套 btrfs 快照启动 / 恢复的完整方案。

![主菜单](screenshots/main.jpg)

> 背景图与 ISLAND 标识为 Frontwing 官方素材，仅作示例。Fedora 标识归 Red Hat 所有。

## 特点

- **1920×1080 星空背景**，左侧压暗保证文字可读
- **九宫格半透明高亮条**（暗色填充 + 白边），在亮色背景上也不糊
- **中文字体**用系统自带的 `unicode.pf2`（GNU Unifont），不方块
- **三层菜单**：主菜单 → 快照列表 → 单个恢复点
- **快照直接从 GRUB 启动**，不用进系统
- **拍快照 / 删快照 / 恢复** 都能在 GRUB 里触发

## 快速安装

```bash
git clone https://github.com/SilverKurali/grub-theme-starry.git
cd grub-theme-starry

sudo mkdir -p /boot/grub2/themes/starry
sudo cp theme/* /boot/grub2/themes/starry/

# 写入配置
echo 'GRUB_THEME="/boot/grub2/themes/starry/theme.txt"' | sudo tee -a /etc/default/grub
sudo sed -i 's/^GRUB_TERMINAL_OUTPUT=.*/GRUB_TERMINAL_OUTPUT="gfxterm"/' /etc/default/grub
sudo sed -i 's/^GRUB_TERMINAL_INPUT=.*/GRUB_TERMINAL_INPUT="console"/' /etc/default/grub
grep -q '^GRUB_GFXMODE=' /etc/default/grub || echo 'GRUB_GFXMODE=1920x1080,1280x720,auto' | sudo tee -a /etc/default/grub

sudo grub2-mkconfig -o /boot/grub2/grub.cfg
sudo reboot
```

**换背景**：把任意 1920×1080 的 PNG 命名成 `background.png` 覆盖 `theme/background.png` 即可。JPEG 也能用（改 `theme.txt` 里的 `desktop-image`），但 PNG 解码更稳。

## 目录

```
theme/          theme.txt + background.png + 九宫格 pixmap + unicode.pf2
scripts/        btrfs 快照方案（可选）
docs/           安装细节、踩坑清单
screenshots/    预览图
```

## 快照方案（可选）

`scripts/` 里是一套让 GRUB 能直接启动 btrfs 快照的东西：

| 文件 | 作用 |
|---|---|
| `40_custom` | 放进 `/etc/grub.d/`，`grub2-mkconfig` 时扫描 `/snapshots/` 生成三层菜单 |
| `01_gfxpayload` | `set gfxpayload=keep`，必须在 `blscfg` 之前 |
| `snapshot.sh` | 拍快照：只读恢复点 + 可写副本 + 试验副本 |
| `rollback.sh` | 命令行回滚 |
| `island-snapshot-wizard` | 开机向导（zenity），从恢复点启动后询问是否永久恢复 |
| `island-boot-action` | GRUB 里选「拍/删快照」后的开机执行器 |
| `island-fstab-patch.py` | 改 fstab 里 `/` 行的 `subvol=` |

**装之前先读 `docs/PITFALLS.md`**，那里面全是踩过的坑，能省几个小时。

## 已知限制

- **启动瞬间会有个黑框**：`console` 输入终端自带的 VGA 文本窗口。换成 `at_keyboard` 能消掉，但 UEFI 机器上键盘会失灵。二者只能选一个。
- **GRUB 不能写 btrfs 元数据**，所以「拍快照 / 删快照」实际是「启动 → 脚本执行 → 自动重启」，会看到两次开机。
- **GRUB 运行时不展开 glob**，快照列表必须在 `grub2-mkconfig` 时生成。

## License

代码部分 MIT，见 `LICENSE`。

`unicode.pf2` 来自 GNU Unifont（GPLv2 + 字体嵌入例外）。

`background.png` 使用《ISLAND》（Frontwing / Key）的官方主视觉图，仅作为主题示例随仓库提供，**版权归 Frontwing 所有**。这不是开源素材，请勿商用；如需公开分发或商用，请替换成自己的图片：

```bash
cp your-wallpaper.png theme/background.png
```

其余部分（theme.txt、九宫格 pixmap、脚本、文档）均为 MIT，可自由使用。
