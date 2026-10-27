# comfyui-migrate-data: one-time merge migration of the legacy repo-local
# data/ directory into the XDG data dir (~/.local/share/comfyui by default).
#
# Semantics:
#   - For each top-level subdir of data/ (models, output, input, user,
#     custom_nodes, ...) and each entry one level inside it, move the entry
#     into the matching XDG subdir, UNLESS an entry of that name already
#     exists there (collision) or the entry is a symlink (e.g. the
#     data/custom_nodes/ollama_imagegen symlink into the repo, which is left
#     alone).
#   - Top-level regular files directly in data/ are moved by the same rule.
#   - A full collision pre-scan runs over every planned move before anything
#     is moved. If ANY collision is found, all collisions are reported, the
#     script exits non-zero, and NOTHING is moved.
#   - After a successful move, now-empty source directories are removed with
#     rmdir (never rm -r); the legacy ollama_imagegen symlink is left as-is.
#   - Idempotent: if no regular files remain under data/, prints "nothing to
#     migrate" and exits 0.
#   - Cross-filesystem moves are handled transparently by `mv` (copy+unlink
#     internally). A failure partway through a run leaves already-moved
#     entries in their new location and leaves everything else untouched;
#     re-running the script is always safe.
#   - Supports --dry-run to print the planned moves without performing them.

usage() {
  cat <<'EOF'
Usage: comfyui-migrate-data [--dry-run]

Merge-migrates ./data (legacy repo-local ComfyUI data) into the XDG data dir
(${XDG_DATA_HOME:-$HOME/.local/share}/comfyui). Refuses and moves nothing on
any name collision. Safe to re-run.
EOF
}

dry_run=0
case "${1:-}" in
--dry-run)
  dry_run=1
  ;;
-h | --help)
  usage
  exit 0
  ;;
"") ;;
*)
  usage >&2
  exit 1
  ;;
esac

comfyui_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
src_root="$comfyui_root/data"
dest_root="${COMFYUI_DATA_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/comfyui}"

if [ ! -d "$src_root" ] || [ -z "$(find "$src_root" -type f -print -quit 2>/dev/null)" ]; then
  echo "nothing to migrate"
  exit 0
fi

moves=()
collisions=()

# Top-level regular files directly in data/.
while IFS= read -r -d '' entry; do
  name="$(basename "$entry")"
  dest="$dest_root/$name"
  if [ -e "$dest" ] || [ -L "$dest" ]; then
    collisions+=("$entry -> $dest")
  else
    moves+=("$entry:$dest")
  fi
done < <(find "$src_root" -mindepth 1 -maxdepth 1 -type f -print0)

# One level inside each top-level subdir of data/.
while IFS= read -r -d '' subdir; do
  subname="$(basename "$subdir")"
  dest_subdir="$dest_root/$subname"
  while IFS= read -r -d '' entry; do
    if [ -L "$entry" ]; then
      continue
    fi
    name="$(basename "$entry")"
    dest="$dest_subdir/$name"
    if [ -e "$dest" ] || [ -L "$dest" ]; then
      collisions+=("$entry -> $dest")
    else
      moves+=("$entry:$dest")
    fi
  done < <(find "$subdir" -mindepth 1 -maxdepth 1 -print0)
done < <(find "$src_root" -mindepth 1 -maxdepth 1 -type d -print0)

if [ "${#collisions[@]}" -gt 0 ]; then
  echo "comfyui-migrate-data: refusing — name collisions found, nothing moved:" >&2
  for collision in "${collisions[@]}"; do
    echo "  $collision" >&2
  done
  exit 1
fi

if [ "${#moves[@]}" -eq 0 ]; then
  echo "nothing to migrate"
  exit 0
fi

for move in "${moves[@]}"; do
  src="${move%%:*}"
  dest="${move#*:}"
  if [ "$dry_run" -eq 1 ]; then
    echo "would move: $src -> $dest"
    continue
  fi
  mkdir -p "$(dirname "$dest")"
  echo "moving: $src -> $dest"
  mv "$src" "$dest"
done

if [ "$dry_run" -eq 1 ]; then
  exit 0
fi

# Remove now-empty source dirs (never rm -r); leave the ollama_imagegen
# symlink and any non-empty dirs alone.
while IFS= read -r -d '' subdir; do
  rmdir "$subdir" 2>/dev/null || true
done < <(find "$src_root" -mindepth 1 -maxdepth 1 -type d -print0)

rmdir "$src_root" 2>/dev/null || true

echo "migration complete"
