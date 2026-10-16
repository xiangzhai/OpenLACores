#!/usr/bin/env bash
#
# Compare the IPC of the current (TAGE) build against a baseline git ref that
# still uses the original BTB direction predictor.  The only source difference
# between the two builds is the RTL front end, so running the same image over
# the same retired-instruction window isolates the branch-predictor effect.
#
# Usage:
#   compare_tage.sh TAGE_EMU BASE_REF BASE_WORKTREE ROOT NAME:IMAGE:MAX_COMMITS...
#
# Results are printed as a table: IPC = commits / cycles, gain = base/tage - 1.
set -euo pipefail

tage_emu=${1:?missing TAGE emulator}
base_ref=${2:?missing baseline git ref}
base_wt=${3:?missing baseline worktree path}
root=${4:?missing repository root}
shift 4

if ! command -v verilator >/dev/null 2>&1; then
    echo "error: verilator not found in PATH" >&2
    exit 1
fi
if [ ! -d "${root}/verify/loong-emu/include" ]; then
    echo "error: ${root}/verify/loong-emu is missing; build the reference model first" >&2
    exit 1
fi

# Prepare (or reuse) a detached worktree at the baseline ref.
git -C "${root}" worktree prune
if [ ! -d "${base_wt}" ]; then
    echo "[compare] creating baseline worktree ${base_wt} at ${base_ref}" >&2
    git -C "${root}" worktree add --detach -f "${base_wt}" "${base_ref}"
fi
# The reference-model tree is an untracked dependency of the main checkout.
if [ ! -e "${base_wt}/verify/loong-emu" ]; then
    ln -s "${root}/verify/loong-emu" "${base_wt}/verify/loong-emu"
fi

base_emu="${base_wt}/verify/verilator/build/$(basename "${tage_emu}")"
if [ ! -x "${base_emu}" ]; then
    jobs="${JOBS:-}"
    case "${jobs}" in ''|0) jobs=$(nproc 2>/dev/null || echo 1);; esac
    echo "[compare] building baseline emulator (${base_ref}) ..." >&2
    make -C "${base_wt}/verify/verilator" JOBS="${jobs}"
fi

# Runs one bounded window and echoes "cycles commits".
run_one() {
    local emu=$1 image=$2 commits=$3 log
    log=$("${emu}" --no-diff --image "${image}" --max-commits "${commits}" \
        --quiet-uart 2>&1 >/dev/null || true)
    printf '%s\n' "${log}" \
        | sed -n 's/.*\[sim\] cycles=\([0-9][0-9]*\) commits=\([0-9][0-9]*\).*/\1 \2/p' \
        | tail -n1
}

printf '%-12s %10s %13s %13s %10s %10s %9s\n' \
    benchmark commits cycles_base cycles_tage IPC_base IPC_tage gain
for spec in "$@"; do
    IFS=: read -r name image commits <<<"${spec}"
    if [ ! -f "${image}" ]; then
        echo "[compare] skip ${name}: image not found: ${image}" >&2
        continue
    fi

    read -r b_cyc b_cmt < <(run_one "${base_emu}" "${image}" "${commits}")
    read -r t_cyc t_cmt < <(run_one "${tage_emu}" "${image}" "${commits}")
    if [ -z "${b_cyc}" ] || [ -z "${t_cyc}" ]; then
        echo "[compare] skip ${name}: could not read sim counters" >&2
        continue
    fi

    awk -v n="${name}" -v bc="${b_cyc}" -v tc="${t_cyc}" \
        -v bm="${b_cmt}" -v tm="${t_cmt}" 'BEGIN {
            ipc_b = (bc > 0) ? bm / bc : 0;
            ipc_t = (tc > 0) ? tm / tc : 0;
            gain  = (tc > 0) ? (bc / tc - 1) * 100 : 0;
            printf "%-12s %10d %13d %13d %10.5f %10.5f %8.3f%%\n",
                   n, tm, bc, tc, ipc_b, ipc_t, gain;
        }'
done
