# 踩坑清单

GRUB 主题看起来是纯配置，实际上有一堆"写了不生效、写错了整个主题不加载"的坑。
这份清单是按实际调试顺序记录的，每条都实测过。

## 一、语法层

### 1. `theme.txt` 用 `=`，不是 `:`

```ini
# 对
left = 5%
width = 30%

# 错（会被忽略，且不报错）
left: 5%
```

`desktop-image` 和 `title-text` 这类顶层属性用的是 `:`，但 `boot_menu` / `label` 块里的属性用 `=`。混用不会报错，只会静默失效 —— 这是最难查的一类。

### 2. `title-text` 不是合法属性

```ini
title-text: "GRUB Boot Menu"     # 整主题加载失败
```

报错：

```
error: ../../grub-core/gfxmenu/theme_loader.c:read_property:723:
       property value invalid: enclose literal values in quotes
```

`title-text` 只在某些版本里被识别，写错类型就会让**整个主题**拒绝加载。想压掉默认标题，用空字符串：

```ini
title-text: ""
```

### 3. 属性值带空格要加引号

```ini
item_font = "Unifont Regular 16"   # 对
item_font = Unifont Regular 16     # 错
```

## 二、图片层

### 4. 九宫格边切片尺寸必须等于圆角尺寸

`select_*.png` 是九宫格（9-slice）。切片规则是：角 = R×R，边 = (S-2R)×R，中心 = (S-2R)×(S-2R)。

```python
# 32×32 画布，圆角 8
_n  = 16×8      # 对：高度 = R
_n  = 16×1      # 错：边框在两端断开，中间是空的
_w  = 8×16      # 对
_w  = 1×16      # 错
_c  = 16×16     # 对
```

切成 1px 的边，GRUB 平铺时只在两端画一次，中间没有边框 —— 看起来就是"框断成两截"。

### 5. `select.png` 单文件形式不被支持

```ini
selected_item_pixmap_style = "select.png"     # 无效
selected_item_pixmap_style = "select_*.png"   # 有效
```

必须用九宫格。单文件写了不报错，但完全不显示。

### 6. JPEG 解码器可能中途失败

1920×1080 的基线 JPEG，GRUB 的 jpeg 解码器在部分版本上会解到某个 MCU 行就停，留下半边黑屏。

**用 PNG。** 2 MB 的 PNG 比 700 KB 的 JPEG 稳得多，ESP 通常有几百 MB 放得下。

### 7. 背景图要用 PNG 的另一个理由

`desktop-image` 指向的文件如果格式不认识，GRUB 会 fallback 到纯色背景，**不会报错**。所以"背景没了"往往是路径或格式问题，不是主题问题。

## 三、终端层

### 8. `GRUB_GFXPAYLOAD_LINUX=keep` 在 BLS 模式下被忽略

Fedora 用 `blscfg` 在运行时从 `/boot/loader/entries/` 生成 menuentry，`10_linux` 脚本不输出任何 menuentry。所以写进 `GRUB_GFXPAYLOAD_LINUX` 的值**没有任何地方会用到**。

必须用独立脚本，在 `blscfg` 之前直接 `set`：

```bash
# /etc/grub.d/01_gfxpayload
#!/bin/sh
echo "set gfxpayload=keep"
```

生成后的 grub.cfg 里它出现在 132 行，而 `blscfg` 在 196 行 —— 顺序对了才生效。

### 9. `at_keyboard` 会让 UEFI 机器的键盘失灵

```bash
GRUB_TERMINAL_INPUT="at_keyboard"    # PS/2 驱动
```

`at_keyboard` 直接读 8042 控制器。UEFI 固件已经接管了键盘，再让 GRUB 去抢，结果是**一个键都收不到**。

只在这几种情况能work：真·PS/2 键盘、BIOS 里关掉了 Legacy USB Support、或者老主板。

### 10. `console` 输入终端会画一个黑框

```bash
GRUB_TERMINAL_INPUT="console"        # 键盘正常，但有黑框
```

`console` 作为输入终端被启用时，GRUB 会同时初始化它的显示部分 —— 在 gfxterm 的 1920×1080 画布上开一个 80×25 的 VGA 文本窗口。

平时菜单盖住它，但执行 `linux` 加载内核的瞬间会露出来，就是那个"启动时闪一下的黑框"。

**这两个只能选一个**：键盘可用（有黑框）或键盘失灵（无黑框）。

### 11. `GRUB_TERMINAL_INPUT="at_keyboard console"` 一样会开窗口

因为 `console` 在里面。两个都写等于既要 PS/2 又要 VGA 窗口。

## 四、菜单结构层

### 12. `/boot/grub2/custom.cfg` 不会被自动 source

Fedora 的 grub.cfg 里没有 `source custom.cfg`（grep 计数 0）。要加自定义条目必须写进 `/etc/grub.d/40_custom`，让 `grub2-mkconfig` 生成。

### 13. `menuentry` 里的 `$变量` 是运行时展开

```sh
menuentry "从快照启动（$snap_label）" {
    linux /vmlinuz rootflags=subvol=$snap_subvol
}
```

`grub2-mkconfig` 生成时不会替换，GRUB 启动时才展开。所以改 `/boot/grub2/snapshot-info.cfg` 里的变量，重启后菜单就变了 —— 不用重新 mkconfig。

### 14. GRUB 运行时不展开 glob

```sh
for d in /snapshots/root-2*; do      # 不展开！
    menuentry "快照 $d" { ... }
done
```

菜单里会原样显示 `/snapshots/root-2*`。**GRUB 的 for 只遍历已展开的参数，不做文件名展开。**

所以快照列表必须在 `grub2-mkconfig` 时（用普通 shell）生成。

### 15. `configfile` 在 menuentry 里会失败

```sh
menuentry "切换" {
    configfile /grub2/other.cfg      # error: not a regular file
}
```

即使 `ls /grub2/` 能看到文件。`configfile` 在菜单项上下文里对 `$root` 的解析有问题，用 `set prefix=...; normal` 也没完全解决。

**可行的替代**：直接 `set prefix=(设备)/目录; normal`，或者把配置合并进主 grub.cfg。

### 16. 只读快照不能 `rw` 挂载

```sh
linux /vmlinuz rootflags=subvol=snapshots/root-20261108-0522 rw
```

只读 subvolume 挂 `rw` 会失败，系统起不来。要启动必须用可写克隆：

```sh
btrfs subvolume snapshot /snapshots/root-xxx /snapshots/root-xxx-rw
btrfs property set /snapshots/root-xxx-rw ro false
```

## 五、Btrfs 层

### 17. 卸载后内核仍持有设备

`umount` 之后 `wipefs` / `mkfs` 报 `设备或资源忙`，`btrfs filesystem show` 里还能看到。

```bash
echo 1 | sudo tee /sys/block/sdX/device/delete
for h in /sys/class/scsi_host/host*/scan; do echo "- - -" | sudo tee $h; done
```

设备会重新枚举（可能改名），之后才能格式化。

### 18. `btrfs property set ... ro false` 只对可写快照有意义

对只读快照执行会报错。顺序必须是：先 `subvolume snapshot`（不带 `-r`），再 `property set ro false`。

## 六、调试层

### 19. `videoinfo` 在 Fedora 上不存在

Fedora 把 GRUB 模块全编进 `grubx64.efi`，`/boot/grub2/x86_64-efi/` 是空的。`videoinfo` 不在里面，敲了报 `can't find command`。

能用的诊断命令：`echo $gfxmode`、`echo $gfxpayload`、`ls`、`set`。

### 20. 验证主题是否真的加载

最快的办法：故意写错一个属性，如果 GRUB 报错，说明主题在加载；如果不报错且界面变回默认，说明路径错了。

或者看 `/boot/grub2/grub.cfg` 里有没有 `set theme=`。

### 21. QEMU 验证主题时分辨率只有 800×600

`-vga std` 在 OVMF 下最高 800×600。1920×1080 的主题在测试环境里文字会被截断（`width = 30%` 只有 240px）。

临时把 `width = 30%` 改成 `90%`、`top = 44%` 改成 `34%`、`height = 42%` 改成 `62%` 才能看全。

**真机是 1920×1080，`width=30%` 够用。**

### 22. `pkill -x qemu-system-x86_64` 永远失败

Linux 的 `comm` 字段上限 15 字符，进程名被截成 `qemu-system-x86`，`-x` 精确匹配不上。

```bash
sudo pkill -9 -f '[q]emu-system'     # 方括号防自杀
pgrep -c qemu-system                 # 确认归零
```

不用方括号的话，`pkill -f` 会匹配到执行它的那个 bash 自己。

## 七、别的

### 23. TTY 里打不出中文

`Ctrl+Alt+F3` 的 TTY 没有输入法，中文路径敲不出来。**所有救援脚本的文件名和内容都应该是纯 ASCII。**

检查：

```bash
find /path/to/rescue | grep -P '[^\x00-\x7F]'
```

### 24. 盘符每次重启都可能变

同一块盘在 `/dev/nvme0n1` 和 `/dev/nvme1n1` 之间跳是常事（取决于枚举顺序）。**任何脚本都不要写死 `/dev/nvmeXnY`，一律用 UUID。**

```bash
blkid -t PARTUUID=xxx        # 找分区
/dev/disk/by-uuid/<UUID>     # 挂载
```
