#!/bin/bash
# 拍一个 btrfs 快照，并同步更新 GRUB 菜单里的「从快照启动」入口
# 每个恢复点会自动建一个可写副本（-rw），供 GRUB 子菜单里的「确定恢复/只看看」使用
set -u

MNT_SNAP="/snapshots"
SNAP_NAME="root-restore"          # 试验副本（可写，随便改）
KEEP_READONLY=3                   # 保留最近几个恢复点
INFO="/boot/grub2/snapshot-info.cfg"
BOOT_UUID="27288f90-6d80-458b-b91a-9c01ec15b91b"

C_OK=$'\033[32m'; C_ERR=$'\033[31m'; C_DIM=$'\033[2m'; C_END=$'\033[0m'
ok()  { printf '%s✓%s %s\n' "$C_OK" "$C_END" "$*"; }
err() { printf '%s✗%s %s\n' "$C_ERR" "$C_END" "$*"; }
dim() { printf '%s%s%s\n' "$C_DIM" "$*" "$C_END"; }

[ "$(id -u)" -eq 0 ] || { echo "要用 sudo 跑：sudo $0"; exit 1; }

TS_LABEL=$(date '+%Y-%m-%d %H:%M')
TS_ID=$(date '+%Y%m%d-%H%M%S')
RO_NAME="root-$TS_ID"
RW_NAME="${RO_NAME}-rw"

mountpoint -q "$MNT_SNAP" || mount "$MNT_SNAP" || { err "挂载 /snapshots 失败"; exit 1; }

# 1) 只读恢复点（历史存档，永久锁定）
echo "→ 拍恢复点 $RO_NAME"
btrfs subvolume snapshot -r / "$MNT_SNAP/$RO_NAME" || { err "快照失败"; exit 1; }
ok "恢复点已建（只读）"

# 2) 同一个恢复点的可写副本（GRUB 从这份启动）
echo "→ 建可写副本 $RW_NAME"
btrfs subvolume snapshot "$MNT_SNAP/$RO_NAME" "$MNT_SNAP/$RW_NAME" >/dev/null || {
    err "建可写副本失败"; exit 1; }
btrfs property set "$MNT_SNAP/$RW_NAME" ro false
ok "可写副本已建"

# 3) 重建试验副本 root-restore（永远是最新拍的这一份）
if btrfs subvolume show "$MNT_SNAP/$SNAP_NAME" >/dev/null 2>&1; then
    echo "→ 删除旧的 $SNAP_NAME"
    btrfs subvolume delete "$MNT_SNAP/$SNAP_NAME" >/dev/null || { err "删旧试验副本失败"; exit 1; }
fi
echo "→ 建试验副本 $SNAP_NAME"
btrfs subvolume snapshot / "$MNT_SNAP/$SNAP_NAME" >/dev/null || { err "建试验副本失败"; exit 1; }
ok "试验副本已建（可写）"

# 4) 更新 GRUB 变量文件
cat > "$INFO" <<EOF
# 由 拍快照.sh 自动生成，不要手改
set snap_subvol="snapshots/$SNAP_NAME"
set snap_label="$TS_LABEL"
EOF
chmod 644 "$INFO"
ok "已写 $INFO"

# 5) 重新生成 grub.cfg
if grub2-mkconfig -o /boot/grub2/grub.cfg >/dev/null 2>&1; then
    ok "grub.cfg 已重新生成"
else
    err "grub2-mkconfig 失败，菜单可能没更新"
fi

# 6) 清理多余恢复点（只读 + 对应 -rw 一起删，保留最近 $KEEP_READONLY 个）
mapfile -t OLD < <(ls -1d "$MNT_SNAP"/root-2* 2>/dev/null | grep -v -- '-rw$' | sort | head -n -"$KEEP_READONLY")
if [ "${#OLD[@]}" -gt 0 ]; then
    echo "→ 清理 ${#OLD[@]} 个旧恢复点"
    for p in "${OLD[@]}"; do
        n=$(basename "$p")
        btrfs subvolume delete "$p" >/dev/null 2>&1 && dim "  删 $n"
        [ -d "$MNT_SNAP/${n}-rw" ] && btrfs subvolume delete "$MNT_SNAP/${n}-rw" >/dev/null 2>&1 && dim "  删 ${n}-rw"
    done
fi

# 7) 汇报
echo
echo "=== 当前快照 ==="
btrfs subvolume list "$MNT_SNAP" 2>/dev/null | awk '{print "  " $NF}'
echo
echo "=== 磁盘 ==="
df -h "$MNT_SNAP" | tail -1
echo
ok "完成。GRUB 里：从快照启动 → 恢复点 $TS_LABEL → 确定恢复 / 只看看"
