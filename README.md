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

**官方原图**放在 `theme/original/`：

| 文件 | 尺寸 | 来源 |
|---|---|---|
| `official-hero-1920x620.jpg` | 1920×620 | Steam 库页面横幅 |
| `official-keyvisual-1438x810.jpg` | 1438×810 | Steam 商店页背景 |
| `official-logo.png` | 588×345 RGBA | 官网 logo |
| `official-icon-256.png` | 256×256 RGBA | 游戏图标 |
| `composite-background.jpg` | 1920×1080 | 合成后的成品（= `theme/background.png` 的 JPEG 版） |

`screenshots/pixmaps-source/` 里是九宫格切片的原始小图（32×32），可以对照 `theme/select_*.png` 看切法。

这两张原图**不能直接做 GRUB 背景**：1920×620 是 3.1:1，塞进 16:9 必然要么裁掉角色的脸、要么上下留黑边；1438×810 比例对了但分辨率不够 1920×1080。

`background.png` 是在 `official-keyvisual-1438x810.jpg` 基础上做的：放大到 1920×1080 → 左侧加暗色渐变（保证菜单文字可读）→ 左上角叠官方 logo → 右下角叠 Fedora wordmark。

## 效果

**真机启动截图**（QEMU + OVMF 跑的真 GRUB 2.12）：

![真机](screenshots/real-boot.png)

**三层菜单**：

| 主菜单 | 快照列表 | 恢复点 |
|---|---|---|
| ![主](screenshots/main.jpg) | ![快照](screenshots/snapshots.jpg) | ![恢复](screenshots/restore.jpg) |

**只换背景、不装快照方案**的样子：

![纯主题](screenshots/wallpaper-preview.jpg)

**九宫格高亮条特写**（暗色填充 + 白边，在亮背景上也不糊）：

![玻璃条](screenshots/glass-bar-preview.jpg)

## 目录

```
theme/          theme.txt + background.png + 九宫格 pixmap + unicode.pf2
theme/original/ 官方素材原图（未处理，仅供对照）
screenshots/    各层预览 + 真机截图
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

**PolyForm Noncommercial 1.0.0** — 仅限个人学习、研究、自用。

- ✅ 自己用、改、分享给朋友
- ✅ 研究 GRUB 主题怎么写
- ✅ 在个人博客/视频里展示和讲解
- ❌ 商业用途（卖给客户、打包进产品、收费安装）
- ❌ 公司内部部署
- ❌ 以营利为目的的服务

完整条款见 [LICENSE](LICENSE)。

**特例：**

| 文件 | 许可证 |
|---|---|
| `theme/unicode.pf2` | GNU Unifont，GPLv2 + 字体嵌入例外（保持原许可） |
| `theme/background.png`、`theme/original/*` | 《ISLAND》官方素材，版权归 Frontwing。仅作示例，**禁止商业使用**。要再分发或商用请先换成自己的图 |

**想商用怎么办**：把 `theme/background.png` 换成你自己的图，`theme.txt` 和九宫格 pixmap 是我写的，那时可以来找我谈授权。
