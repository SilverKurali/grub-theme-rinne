#!/usr/bin/env python3
"""把 fstab 里 / 那行的挂载选项改成 subvol=snapshots/root-active"""
import sys

path, uuid = sys.argv[1], sys.argv[2]
lines = open(path).read().splitlines()
out = []
for ln in lines:
    parts = ln.split()
    if len(parts) >= 3 and parts[0] == f"UUID={uuid}" and parts[1] == "/" and parts[2] == "btrfs":
        opts = [o for o in parts[3].split(",") if o and not o.startswith("subvol=")]
        opts.insert(0, "subvol=snapshots/root-active")
        parts[3] = ",".join(opts)
        out.append(" ".join(parts))
    else:
        out.append(ln)
open(path, "w").write("\n".join(out) + "\n")
print("  fstab 已改：", [l for l in out if l.startswith("UUID=" + uuid) and " / " in l][0])
