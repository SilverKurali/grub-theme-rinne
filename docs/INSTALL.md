# 安装

## 前提

- GRUB 2.06 以上（本文在 GRUB 2.12-83.fc45 上测试）
- UEFI 启动
- 分辨率至少 1920×1080（或改 `GRUB_GFXMODE`）

## 只要主题

```bash
sudo mkdir -p /boot/grub2/themes/starry
sudo cp theme/* /boot/grub2/themes/starry/
sudo chmod -R a+rX /boot/grub2/themes/starry
```

改 `/etc/default/grub`：

```bash
GRUB_THEME="/boot/grub2/themes/starry/theme.txt"
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
set theme="/boot/grub2/themes/starry/theme.txt"
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

## 卸载

```bash
sudo rm -f /etc/grub.d/40_custom /etc/grub.d/01_gfxpayload
sudo rm -rf /boot/grub2/themes/starry
sudo sed -i '/GRUB_THEME/d' /etc/default/grub
sudo grub2-mkconfig -o /boot/grub2/grub.cfg
```

快照本身在 `/snapshots/`，删掉对应的 subvolume 即可。

## 验证清单

装完重启前，逐条检查：

- [ ] `ls /boot/grub2/themes/starry/` 能看到 `theme.txt`、`background.png`、18 个 `select_*.png` / `menu_*.png`、`unicode.pf2`
- [ ] `grep 'set theme' /boot/grub2/grub.cfg` 有输出
- [ ] `grep 'terminal_output gfxterm' /boot/grub2/grub.cfg` 有输出
- [ ] `grep 'gfxpayload=keep' /boot/grub2/grub.cfg` 在 `blscfg` 之前
- [ ] `sudo grub2-script-check /boot/grub2/grub.cfg` 通过
- [ ] 备份了旧的 `grub.cfg` 和 `/etc/default/grub`

**出问题怎么救**：GRUB 菜单里按 `e` 编辑启动项，在 `linux` 行末尾加 `rootflags=subvol=/`（如果根盘没换过 subvolume 就不用），或者从 Live USB 挂回原来的 grub.cfg。
