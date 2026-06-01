#!/usr/bin/env bash
# First-contact Hellgate probe: gather everything we need to know about the
# cluster in one shot, write a single report, exit. Run this on the Hellgate
# login node (hellgate.rci.umt.edu) the first time we have access -- it
# answers the open questions in docs/HELLGATE_FVS.md "[confirm on cluster]"
# without requiring any of our images yet, then runs ONE minimal Apptainer +
# SLURM end-to-end test to prove the path is alive.
#
# Safe: read-only except for files under $WORKDIR (default ./hellgate_probe/),
# never writes to BeeGFS shared areas, never installs anything, never modifies
# user config. Idempotent (subsequent runs replace WORKDIR).
#
# Usage (on Hellgate):
#   git clone <fvs-containers> && cd fvs-containers
#   bash cluster/hellgate_probe.sh                   # report -> ./hellgate_probe/report.md
#
# Env:
#   WORKDIR    output directory (default: ./hellgate_probe)
#   PARTITION  partition to use for the SLURM smoke test (default: auto-pick first available)
#   ACCOUNT    SLURM account to use, if your cluster requires it
#   SKIP_SLURM  =1 to skip the SLURM submit (env probe only)

set -uo pipefail   # not -e: a single failing probe must not abort the whole report

WORKDIR="${WORKDIR:-./hellgate_probe}"
mkdir -p "$WORKDIR/logs"
# Absolutize WORKDIR so the smoke-test section (which `cd`s into it) still appends
# to the real report; a relative $REPORT would misresolve after that cd and the
# smoke output would land in a stray $WORKDIR/$WORKDIR/report.md instead.
WORKDIR="$(cd "$WORKDIR" && pwd)"
REPORT="${WORKDIR}/report.md"
LOG="${WORKDIR}/probe.log"

# All output streams into the report (sectioned) plus a verbose log.
exec 3>&1   # fd 3 = console
{
  echo "# Hellgate probe — $(date -Is)"
  echo
  echo "Host: \`$(hostname -f 2>/dev/null || hostname)\`  User: \`${USER:-?}\`  PWD: \`$(pwd)\`"
  echo "Probe script: \`cluster/hellgate_probe.sh\` (commit \`$(git -C "$(dirname "$0")/.." rev-parse --short HEAD 2>/dev/null || echo unknown)\`)"
  echo
} | tee "$REPORT" >&3

section() { { echo; echo "## $*"; echo; } | tee -a "$REPORT" >&3; }
note()    { { echo "- $*"; } | tee -a "$REPORT" >&3; }
fence()   { { echo; echo '```'; cat; echo '```'; echo; } | tee -a "$REPORT" >&3; }
have()    { command -v "$1" >/dev/null 2>&1; }

# ------------------------------------------------------------ shell / module ---
section "Shell, OS, modules"
note "Shell: \`$SHELL\` (bash $BASH_VERSION)"
note "OS: $(awk -F= '/^PRETTY_NAME=/ {gsub(/"/, "", $2); print $2; exit}' /etc/os-release 2>/dev/null || uname -sr)"
note "Kernel: $(uname -r)"
if have module; then
  note "Module system present."
  { module --version 2>&1 || true; } | fence
  note "Default loaded modules:"
  { module list 2>&1 || true; } | fence
else
  note "No \`module\` command on PATH (Lmod/Tcl Modules might still be available via shell init)."
fi

# ----------------------------------------------------------------- Apptainer ---
section "Apptainer / Singularity"
if have apptainer; then APPT=apptainer
elif have singularity; then APPT=singularity
else APPT=""; fi
if [ -n "$APPT" ]; then
  note "Engine: \`$APPT\` at \`$(command -v "$APPT")\`"
  { "$APPT" --version 2>&1 || true; } | fence
  # fakeroot probe: a successful `--fakeroot exec docker://hello-world echo hi` proves end-to-end.
  # First just check the subuid/subgid map exist for this user.
  if [ -f /etc/subuid ] && grep -q "^${USER}:" /etc/subuid 2>/dev/null; then
    note "subuid entry present for \`${USER}\` (a prerequisite for \`--fakeroot\`)."
  else
    note "No subuid entry for \`${USER}\` in /etc/subuid -- \`--fakeroot\` likely unavailable. Confirm with RCI."
  fi
  # FUSE: needed for `.sif` mount-as-overlay (some flows). Not strictly needed for `exec` on a SIF.
  if [ -e /dev/fuse ]; then note "\`/dev/fuse\` present (required for some overlay/sandbox flows)."
  else                       note "\`/dev/fuse\` NOT present -- read-only \`.sif\` exec should still work, overlay won't."
  fi
  # User-namespace probe (most newer kernels enable this by default).
  unshare_user_ok=no
  unshare -U true 2>/dev/null && unshare_user_ok=yes
  note "User namespaces (\`unshare -U\`): $unshare_user_ok"
else
  note "**No apptainer/singularity on PATH.** Try \`module avail apptainer\` / \`module load apptainer\`, then re-run."
  { module avail 2>&1 | head -40 || true; } | fence
fi

# --------------------------------------------------------------------- SLURM ---
section "SLURM"
if have sinfo && have sbatch; then
  note "sbatch: \`$(command -v sbatch)\`  sinfo: \`$(command -v sinfo)\`"
  { sbatch --version 2>&1 || true; } | fence
  note "Partitions / nodes (\`sinfo -o '%P %a %l %D %C %m %f'\`):"
  { sinfo -o '%P %a %l %D %C %m %f' 2>&1 || true; } | fence
  note "Per-partition default + max walltime (\`sinfo -o '%P %l %L'\`):"
  { sinfo -o '%P %l %L' 2>&1 | sort -u || true; } | fence
  note "Array job limits (\`scontrol show config | grep -E 'MaxArray|MaxJobCount|DefMemPerCPU'\`):"
  { scontrol show config 2>/dev/null | grep -E 'MaxArray|MaxJobCount|DefMemPerCPU|MaxMemPerCPU' || true; } | fence
  if have sacctmgr; then
    note "Account/QOS for \`${USER}\` (\`sacctmgr show assoc user=${USER}\`):"
    { sacctmgr -p show assoc user="${USER}" 2>&1 || true; } | fence
  fi
  if have sshare; then
    note "Fairshare (\`sshare -U\`):"
    { sshare -U 2>&1 || true; } | fence
  fi
  if have squeue; then
    note "Current queue (your jobs, if any):"
    { squeue -u "${USER}" 2>&1 | head -20 || true; } | fence
  fi
else
  note "**No sbatch/sinfo on PATH.** SLURM probably needs \`module load slurm\` or a different login node."
fi

# ----------------------------------------------------------------- filesystems ---
section "Filesystems / quotas"
# Hellgate's user-facing storage is BeeGFS (~800 TB per UM RCI docs); the
# canonical project path is /mnt/beegfs/... Probe a few likely roots and let
# the actual mount table report what's live (some hosts mount /scratch or
# /project too; we probe those just in case).
for p in /home "$HOME" /mnt/beegfs /scratch /project /mnt/scratch /mnt/project; do
  [ -e "$p" ] || continue
  note "\`$p\`: exists ($(stat -c '%U:%G %A' "$p" 2>/dev/null), size $(stat -c '%s' "$p" 2>/dev/null))"
done
note "\`df -h\` (likely-relevant filesystems):"
{ df -hT 2>/dev/null | awk 'NR==1 || /beegfs|home|scratch|project|nfs|gpfs|lustre/' || true; } | fence
# Two candidate shared-container areas: the old BeeGFS path and the generic
# /opt/containers some clusters use. Whichever exists, list it.
for SHARED_CONTAINERS in /mnt/beegfs/projects/resources/Containers /opt/containers /project/containers; do
  if [ -d "$SHARED_CONTAINERS" ]; then
    note "Shared container area \`$SHARED_CONTAINERS\` exists. First 10 entries:"
    { find "$SHARED_CONTAINERS" -maxdepth 1 -mindepth 1 -printf '%M %u:%g %TY-%Tm-%Td %f\n' 2>/dev/null | head -10 || true; } | fence
  fi
done
# BeeGFS-specific quota (no-op on non-BeeGFS layouts).
if have beegfs-ctl; then
  note "BeeGFS quota for \`${USER}\` (\`beegfs-ctl --getquota --uid ${USER}\`):"
  { beegfs-ctl --getquota --uid "${USER}" 2>&1 || true; } | fence
fi
# Generic quota.
if have quota; then
  note "Filesystem quota (\`quota -s\`):"
  { quota -s 2>&1 || true; } | fence
fi

# ---------------------------------------------------------- Login-node egress ---
section "Login-node network egress (for \`apptainer pull docker://...\`)"
probe_url() {
  local label="$1" url="$2"
  if have curl; then
    local code; code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 8 "$url" 2>/dev/null || echo "ERR")"
    note "\`$label\` (\`$url\`): HTTP $code"
  else
    note "\`curl\` not present; skipping $label."
  fi
}
probe_url "GHCR (Vibrant Planet's FVS image)" "https://ghcr.io/v2/vibrant-planet-open-science/usfs-fvs/manifests/FS2026.1"
probe_url "Docker Hub"                         "https://registry-1.docker.io/v2/"
probe_url "PyPI"                               "https://pypi.org/simple/"
probe_url "CRAN"                               "https://cloud.r-project.org/"
probe_url "github.com"                         "https://github.com"
note "Reading these: \`200\`/\`30x\` = reachable. \`401\`/\`403\` from GHCR/Docker = registry reachable (auth is expected for unauthenticated v2 calls); \`000\` or \`ERR\` = blocked."

# ---------------------------------------------------------------------- R ----
section "R availability"
if have Rscript; then
  note "Rscript: \`$(command -v Rscript)\`"
  { Rscript --version 2>&1 || true; } | fence
  note "Default library paths (vanilla R, no project profile):"
  # --vanilla + R_PROFILE_USER=/dev/null bypasses any .Rprofile/renv in the cwd
  # so the probe works whether or not the repo is checked out alongside.
  { R_PROFILE_USER=/dev/null Rscript --vanilla -e 'cat(.libPaths(), sep="\n")' 2>&1 || true; } | fence
else
  note "No Rscript on PATH. If R-on-Hellgate is needed for keyword generation, try \`module avail r\` / \`module load R\`."
  if have module; then { module avail 2>&1 | grep -i '\bR\b\|/r/' | head -20 || true; } | fence; fi
fi

# ---------------------------------------------- End-to-end Apptainer + SLURM ---
section "End-to-end smoke test (Apptainer + SLURM)"
if [ "${SKIP_SLURM:-0}" = "1" ]; then
  note "\`SKIP_SLURM=1\` set; skipping the smoke submit."
elif [ -z "$APPT" ] || ! have sbatch; then
  note "Skipping: need both Apptainer and SLURM."
else
  cd "$WORKDIR" || { note "**cd $WORKDIR failed; skipping smoke test.**"; exit 0; }
  # Tiny self-contained \`.sif\`: a 5MB alpine that echoes its kernel + uname. Pulled
  # from a public registry; if egress fails this whole section reports that loudly.
  if [ ! -f tiny.sif ]; then
    note "Pulling a small public image to a SIF (\`docker://alpine:3.20\`)..."
    if "$APPT" pull --force tiny.sif docker://alpine:3.20 >> logs/pull.log 2>&1; then
      note "OK: \`tiny.sif\` built ($(du -h tiny.sif | cut -f1))."
    else
      note "FAILED to pull. Tail of pull log:"
      { tail -20 logs/pull.log; } | fence
      note "If login-node egress is blocked, build the SIF off-cluster and \`scp\` it in."
    fi
  fi
  if [ -f tiny.sif ]; then
    # Pick a partition if not given.
    if [ -z "${PARTITION:-}" ] && have sinfo; then
      PARTITION="$(sinfo -h -o '%P' | head -1 | tr -d '*')"
      note "Auto-picked PARTITION=\`$PARTITION\` (override via env)."
    fi
    cat > smoke.sbatch <<EOF
#!/bin/bash
#SBATCH --job-name=fvs-probe
#SBATCH --output=logs/smoke_%j.out
#SBATCH --error=logs/smoke_%j.err
#SBATCH --time=00:05:00
#SBATCH --cpus-per-task=1
#SBATCH --mem=512M
${PARTITION:+#SBATCH --partition=$PARTITION}
${ACCOUNT:+#SBATCH --account=$ACCOUNT}
set -euo pipefail
echo "Host: \$(hostname)  SLURM_JOB_ID=\$SLURM_JOB_ID"
$APPT exec tiny.sif sh -c 'echo "in-container: \$(uname -a)"; cat /etc/os-release'
EOF
    note "Submitting smoke job (\`sbatch smoke.sbatch\`)..."
    if sub="$(sbatch --parsable smoke.sbatch 2>>logs/sbatch.log)"; then
      note "Submitted job \`$sub\`. Waiting up to 60s for completion..."
      for _ in $(seq 1 30); do
        sleep 2
        state="$(squeue -h -j "$sub" -o '%T' 2>/dev/null | head -1)"
        [ -z "$state" ] && break          # job has left the queue
      done
      note "Final \`sacct\` for \`$sub\`:"
      { sacct -j "$sub" -o JobID,State,ExitCode,Elapsed,ReqMem,NodeList 2>&1 || true; } | fence
      out="logs/smoke_${sub}.out"
      err="logs/smoke_${sub}.err"
      [ -f "$out" ] && { note "stdout:"; { cat "$out"; } | fence; }
      [ -f "$err" ] && [ -s "$err" ] && { note "stderr:"; { cat "$err"; } | fence; }
    else
      note "**Submit failed.** Tail of sbatch log:"
      { tail -20 logs/sbatch.log; } | fence
    fi
  fi
  cd - >/dev/null || true
fi

# ------------------------------------------------ open questions to confirm ---
section "Open questions for follow-up (per \`docs/HELLGATE_FVS.md\`)"
cat <<'EOF' | tee -a "$REPORT" >&3
Use the sections above to answer:

1. **Partitions & limits** — partition names, default/max walltime, cores/mem per node, `MaxArraySize` (in scontrol output).
2. **Network egress** — did the GHCR/Docker Hub probes succeed? If not, the canonical path is build-off-cluster + `scp`.
3. **fakeroot** — was the subuid entry present? If yes, try `apptainer build --fakeroot fvs_ie.sif <def>` later. If no, ask RCI for an entry, or stay on the off-cluster build path.
4. **Modules** — is `apptainer` on PATH by default, or behind `module load`? Is R available (`module avail r`)?
5. **Storage** — confirm BeeGFS mount paths and per-area quotas (Hellgate's user-facing storage is BeeGFS, ~800 TB per UM RCI docs). Note any shared `Containers` area worth publishing the SIF to.
6. **Account/QOS** — did `sacctmgr` show your association? Note the account name; the sbatch script will need `--account=`.

When done, paste `hellgate_probe/report.md` back to the fvs-containers chat and we'll
calibrate `cluster/fvs_array.sbatch` defaults from it.
EOF

section "Where everything went"
note "Report: \`$REPORT\`"
note "Logs:   \`$WORKDIR/logs/\` (sbatch.log, pull.log, smoke_<jobid>.{out,err})"
note "Tiny test SIF: \`$WORKDIR/tiny.sif\` (safe to delete after review)"

# Mirror the report to the log for archival.
cp "$REPORT" "$LOG"
echo "Done. Report: $REPORT" >&3
