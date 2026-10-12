#!/bin/bash
# docker-lineage-cicd userscript: integrate KernelSU-Next (legacy, manual hooks)
# into kernel/google/redbull before the device build.
#
# Called by docker-lineage-cicd as:  pre-build.sh <codename> <branch>
# Working directory: the Android source tree ($SRC_DIR/<BRANCH_DIR>)
set -euo pipefail

CODENAME="${1:-}"
BRANCH="${2:-}"

# Devices to patch (space separated). redfin/barbet share the same kernel.
KSU_DEVICES="${KSU_DEVICES:-bramble}"
KERNEL_DIR="${KERNEL_DIR:-$PWD/kernel/google/redbull}"
PATCH_DIR="$(dirname "$(readlink -f "$0")")/ksu-patches"
SETUP_URL="https://raw.githubusercontent.com/KernelSU-Next/KernelSU-Next/next/kernel/setup.sh"

log() { echo ">> [$(date)] [ksu] $*"; }

if [[ " $KSU_DEVICES " != *" $CODENAME "* ]]; then
  log "$CODENAME not in KSU_DEVICES ($KSU_DEVICES), skipping"
  exit 0
fi

[ -d "$KERNEL_DIR/.git" ] || [ -f "$KERNEL_DIR/.git" ] || { log "kernel tree $KERNEL_DIR not found"; exit 1; }
[ -d "$PATCH_DIR" ] || { log "patch dir $PATCH_DIR not found"; exit 1; }

cd "$KERNEL_DIR"

# 1. Start from a pristine kernel tree (removes leftovers of earlier runs,
#    including KernelSU-Next/ and the drivers/kernelsu symlink).
log "resetting $KERNEL_DIR"
git reset -q --hard
git clean -q -ffdx

# 2. Add KernelSU-Next (legacy)
log "running KernelSU-Next setup.sh"
curl -LSs "$SETUP_URL" | bash -s 3ade559
[ -L drivers/kernelsu ] || { log "setup.sh did not create drivers/kernelsu"; exit 1; }
git -C KernelSU-Next log -1 --format='>> [ksu] KernelSU-Next at %h (%cd) %s'

# 3. Apply our patches (defconfig + backports).
for p in "$PATCH_DIR"/*.patch; do
  log "applying $(basename "$p")"
  if ! git apply --check "$p"; then
    log "patch $(basename "$p") does not apply cleanly"
    exit 1
  fi
  git apply "$p"
done

# 4. KernelSU-Next's Kbuild edits core kernel sources (fs/, include/,
#    security/selinux) with $(shell sed ...) at the moment make parses it,
#    i.e. in the middle of a parallel kernel build. Evaluate it once now so
#    that any remaining edits are in place before anything is compiled.
#    With the backport patch above this is normally a no-op.
log "pre-evaluating KernelSU-Next Kbuild source edits"
tmpmk="$(mktemp)"
printf 'ksu-preapply:\n\t@:\n' > "$tmpmk"
make -s -C "$KERNEL_DIR" -f "$KERNEL_DIR/drivers/kernelsu/Kbuild" -f "$tmpmk" \
  srctree="$KERNEL_DIR" objtree="$KERNEL_DIR" src=drivers/kernelsu \
  CONFIG_KSU=y CONFIG_KSU_MANUAL_HOOK=y ksu-preapply
rm -f "$tmpmk"

log "kernel tree changes:"
git status --short
log "done for $CODENAME ($BRANCH)"
