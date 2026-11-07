# 安装

## 前提

- GRUB 2.06 以上（本文在 GRUB 2.12-83.fc45 上测试）
- UEFI 启动
- 分辨率至少 1920×1080（或改 `GRUB_GFXMODE`）

## 只要主题

```bash
sudo mkdir -p /boot/grub2/themes/rinne
sudo cp theme/* /boot/grub2/themes/rinne/
sudo chmod -R a+rX /boot/grub2/themes/rinne
```

改 `/etc/default/grub`：

```bash
GRUB_THEME="/boot/grub2/themes/rinne/theme.txt"
GRUB_GFXMODE=1920x1080,1280x720,auto
GRUB_TERMINAL_OUTPUT="gfxterm"
GRUB_TERMINAL_INPUT="console"
```

生成配置：

```bash
sudo grub2-mkconfig -o /boot/grub2/grub.cfg
```

检查：

```bash
grep -E 'set theme|terminal_output|set gfxmode' /boot/grub2/grub.cfg
```

应该能看到：

```
set theme="/boot/grub2/themes/rinne/theme.txt"
terminal_output gfxterm
set gfxmode=1920x1080,1280x720,auto
```

## 连快照方案一起装

### 1. 建快照目录（如果还没有）

```bash
# 找出根分区
ROOT_UUID=$(findmnt -no UUID /)
ROOT_DEV=$(findmnt -no SOURCE /)

sudo btrfs subvolume create /snapshots
echo "UUID=$ROOT_UUID /snapshots btrfs subvol=snapshots,compress=zstd,noatime 0 0" \
    | sudo tee -a /etc/fstab
sudo mount /snapshots
```

### 2. 拍第一个快照

```bash
sudo btrfs subvolume snapshot -r / /snapshots/root-$(date +%Y%m%d-%H%M%S)
```

### 3. 装脚本

```bash
sudo install -m 755 scripts/40_custom             /etc/grub.d/40_custom
sudo install -m 755 scripts/01_gfxpayload         /etc/grub.d/01_gfxpayload
sudo install -m 755 scripts/island-snapshot-wizard /usr/local/bin/
sudo install -m 755 scripts/island-boot-action     /usr/local/bin/
sudo install -m 755 scripts/island-fstab-patch.py  /usr/local/lib/
sudo install -m 644 scripts/island-boot-action.service /etc/systemd/system/
sudo install -m 644 scripts/island-snapshot-wizard.desktop /etc/xdg/autostart/

sudo systemctl daemon-reload
sudo systemctl enable island-boot-action.service
```

### 4. 改脚本里的 UUID 和内核路径

`scripts/40_custom` 开头这几行必须改成你自己的：

```sh
BOOT_UUID="27288f90-..."      # findmnt -no UUID /boot
ROOT_UUID="cd36d682-..."      # findmnt -no UUID /
KERNEL="/vmlinuz-$(uname -r)"
INITRD="/initramfs-$(uname -r).img"
```

**内核升级后要重新改这两行**，否则快照条目会指向已经不存在的 vmlinuz。

### 5. 生成菜单

```bash
sudo grub2-mkconfig -o /boot/grub2/grub.cfg
grep -n 'submenu' /boot/grub2/grub.cfg
```

---

## 可选：让 Fedora 的菜单标题一直是中文

Fedora 的内核条目由 `blscfg` 从 `/boot/loader/entries/*.conf` 里读 `title` 字段生成。**每次内核升级，`kernel-install` 会把 title 重写回英文的 `Fedora Linux (7.2.16-...) 45 (Workstation Edition)`。**

如果嫌麻烦，可以装一个监控单元，一有新条目就自动改回中文：

```bash
sudo install -m 755 scripts/island-bls-titles /usr/local/bin/island-bls-titles
sudo install -m 644 scripts/island-bls-titles.service /etc/systemd/system/
sudo install -m 644 scripts/island-bls-titles.path /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now island-bls-titles.path
```

它监控 `/boot/loader/entries` 目录，一旦有文件变化（内核安装/删除/`grubby` 改动）就：

1. 读每个 `.conf` 的 `version` 字段
2. `7.2.16-300.fc45.x86_64` → `Fedora Linux 45（正常启动 · 7.2.16）`
3. `0-rescue-...` → `Fedora Linux 救援模式（0-rescue）`
4. 有改动才跑 `grub2-mkconfig`

**验证**：

```bash
# 手动改回英文，等 3 秒看它自己变回来
sudo sed -i 's/^title .*/title Fedora Linux (test) 45 (Workstation Edition)/' /boot/loader/entries/*7.2*.conf
sleep 4
grep '^title' /boot/loader/entries/*.conf
# 应该已经是中文

journalctl -u island-bls-titles.service -n 10 --no-pager
```

**这不是必需的。** 如果你不介意英文标题，跳过这步完全没问题——菜单其余部分（快照子菜单、图标、字体）都不受影响。

**卸载**：

```bash
sudo systemctl disable --now island-bls-titles.path
sudo rm -f /etc/systemd/system/island-bls-titles.path \
             /etc/systemd/system/island-bls-titles.service \
             /usr/local/bin/island-bls-titles
sudo systemctl daemon-reload
```

## 卸载

```bash
sudo rm -f /etc/grub.d/40_custom /etc/grub.d/01_gfxpayload
sudo rm -rf /boot/grub2/themes/rinne
sudo sed -i '/GRUB_THEME/d' /etc/default/grub
sudo grub2-mkconfig -o /boot/grub2/grub.cfg
```

快照本身在 `/snapshots/`，删掉对应的 subvolume 即可。

## 验证清单

装完重启前，逐条检查：

- [ ] `ls /boot/grub2/themes/rinne/` 能看到 `theme.txt`、`background.png`、18 个 `select_*.png` / `menu_*.png`、`unicode.pf2`
- [ ] `grep 'set theme' /boot/grub2/grub.cfg` 有输出
- [ ] `grep 'terminal_output gfxterm' /boot/grub2/grub.cfg` 有输出
- [ ] `grep 'gfxpayload=keep' /boot/grub2/grub.cfg` 在 `blscfg` 之前
- [ ] `sudo grub2-script-check /boot/grub2/grub.cfg` 通过
- [ ] 备份了旧的 `grub.cfg` 和 `/etc/default/grub`

**出问题怎么救**：GRUB 菜单里按 `e` 编辑启动项，在 `linux` 行末尾加 `rootflags=subvol=/`（如果根盘没换过 subvolume 就不用），或者从 Live USB 挂回原来的 grub.cfg。
