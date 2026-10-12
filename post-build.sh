#!/bin/bash
# docker-lineage-cicd userscript: undo the KernelSU-Next integration so that
# the next `repo sync` does not fail on a dirty kernel/google/redbull.
#
# Called as: post-build.sh <codename> <build_successful> <branch>
set -uo pipefail

KERNEL_DIR="${KERNEL_DIR:-$PWD/kernel/google/redbull}"

if [ -d "$KERNEL_DIR" ]; then
  echo ">> [$(date)] [ksu] resetting $KERNEL_DIR (device ${1:-?}, success=${2:-?})"
  git -C "$KERNEL_DIR" reset -q --hard
  git -C "$KERNEL_DIR" clean -q -ffdx
fi
exit 0
