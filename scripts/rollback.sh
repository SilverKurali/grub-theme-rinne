#!/bin/bash
# ============================================================
#  把系统永久回滚到某个 btrfs 快照
#  用法：sudo ~/回滚到快照.sh
# ============================================================
set -euo pipefail

SNAPDIR=/snapshots
ROOT_UUID=cd36d682-1940-44ba-be9b-f9b34d9ab752
FSTAB=/etc/fstab
STAMP=$(date +%Y%m%d-%H%M%S)

[ "$(id -u)" = "0" ] || { echo "请用 sudo 运行"; exit 1; }

mountpoint -q "$SNAPDIR" || mount "$SNAPDIR"

# ---------- 1. 列出快照 ----------
mapfile -t snaps < <(ls -1d "$SNAPDIR"/root-2* 2>/dev/null | sort -r)
if [ ${#snaps[@]} -eq 0 ]; then
    echo "没有找到任何快照（$SNAPDIR/root-2*）"
    exit 1
fi

echo "════════════════════════════════════════"
echo "  可用恢复点"
echo "════════════════════════════════════════"
for i in "${!snaps[@]}"; do
    name=$(basename "${snaps[$i]}")
    core=${name#root-}
    datep=${core%%-*}
    timep=${core##*-}
    if [ ${#datep} -eq 8 ]; then
        case ${#timep} in
            6) label="${datep:0:4}-${datep:4:2}-${datep:6:2} ${timep:0:2}:${timep:2:2}:${timep:4:2}" ;;
            4) label="${datep:0:4}-${datep:4:2}-${datep:6:2} ${timep:0:2}:${timep:2:2}" ;;
            *) label="$name" ;;
        esac
    else
        label="$name"
    fi
    printf "  %2d) %s\n" $((i + 1)) "$label"
done
echo

read -rp "回滚到第几个？[1-${#snaps[@]}] : " pick
case "$pick" in
    ''|*[!0-9]*) echo "输入无效"; exit 1 ;;
esac
idx=$((pick - 1))
if [ $idx -lt 0 ] || [ $idx -ge ${#snaps[@]} ]; then
    echo "超出范围"; exit 1
fi

TARGET=$(basename "${snaps[$idx]}")
echo
echo "将回滚到：$TARGET"
echo
echo "流程："
echo "  1) 先把当前状态存成 pre-rollback-$STAMP（万一后悔还能回来）"
echo "  2) 把 $TARGET 克隆成可写的 root-active"
echo "  3) 把 /etc/fstab 的 / 指向 subvol=snapshots/root-active"
echo "  4) 重启后生效"
echo
read -rp "确认？输入 yes 继续 : " ok
[ "$ok" = "yes" ] || { echo "已取消"; exit 0; }

# ---------- 2. 备份当前状态 ----------
echo
echo "[1/3] 备份当前系统状态…"
if [ -d "$SNAPDIR/pre-rollback-$STAMP" ]; then
    echo "  已存在，跳过"
else
    btrfs subvolume snapshot / "$SNAPDIR/pre-rollback-$STAMP"
    echo "  → $SNAPDIR/pre-rollback-$STAMP"
fi

# ---------- 3. 克隆目标快照为可写 ----------
echo "[2/3] 克隆快照为可写…"
if [ -d "$SNAPDIR/root-active" ]; then
    btrfs subvolume delete "$SNAPDIR/root-active" >/dev/null
fi
btrfs subvolume snapshot "$SNAPDIR/$TARGET" "$SNAPDIR/root-active"
btrfs property set "$SNAPDIR/root-active" ro false 2>/dev/null || true
echo "  → $SNAPDIR/root-active（可写）"

# ---------- 4. 改 fstab ----------
echo "[3/3] 修改 /etc/fstab…"
cp "$FSTAB" "$FSTAB.bak.$STAMP"
python3 - "$FSTAB" "$ROOT_UUID" <<'PY'
import sys, re
path, uuid = sys.argv[1], sys.argv[2]
lines = open(path).read().splitlines()
out = []
for ln in lines:
    parts = ln.split()
    if (len(parts) >= 3 and parts[0] == f"UUID={uuid}"
            and parts[1] == "/" and parts[2] == "btrfs"):
        # 保留原有选项里非 subvol 的部分
        opts = [o for o in parts[3].split(",") if o and not o.startswith("subvol=")]
        opts.insert(0, "subvol=snapshots/root-active")
        parts[3] = ",".join(opts)
        out.append(" ".join(parts))
    else:
        out.append(ln)
open(path, "w").write("\n".join(out) + "\n")
PY
grep -E "^UUID=$ROOT_UUID / " "$FSTAB"

echo
echo "════════════════════════════════════════"
echo "  完成。重启后就是 $TARGET 的状态。"
echo "════════════════════════════════════════"
echo
echo "如果重启后进不去系统："
echo "  · 在 GRUB 菜单按 e，找到 linux 那行"
echo "  · 在行尾加： rootflags=subvol=/"
echo "  · 按 Ctrl-X 启动，就回到原来的系统"
echo
echo "撤销这次回滚："
echo "  sudo cp $FSTAB.bak.$STAMP $FSTAB"
echo "  sudo btrfs subvolume delete $SNAPDIR/root-active"
echo
