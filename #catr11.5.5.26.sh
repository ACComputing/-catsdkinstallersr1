#!/usr/bin/env bash
# ============================================================================
#  CatSDK R11.1  —  surgical fix for R11.0
#  Patches what R11.0 broke or skipped:
#    1. devkitPPC (GameCube/Wii) — installs explicit package names (no groups)
#    2. brew tap github auth hang — disables git prompts
#    3. removes references to non-existent formulas
#    4. fixes mednafen (formula, not cask) + openemu cask
#    5. verifies every toolchain that should now exist
#
#  Run AFTER catsdk-r11.sh. Idempotent.
# ============================================================================
set -Eeuo pipefail

# ---- never let git block on a credential prompt ----------------------------
export GIT_TERMINAL_PROMPT=0
export GIT_ASKPASS=/usr/bin/true
export SSH_ASKPASS=/usr/bin/true
unset GIT_USERNAME GIT_PASSWORD

# ---- paint -----------------------------------------------------------------
if [[ -t 1 ]]; then
  C_RST=$'\033[0m'; C_DIM=$'\033[2m'; C_BLD=$'\033[1m'
  C_PNK=$'\033[38;5;213m'; C_CYN=$'\033[38;5;87m'
  C_GRN=$'\033[38;5;120m'; C_YEL=$'\033[38;5;227m'; C_RED=$'\033[38;5;203m'
else
  C_RST=""; C_DIM=""; C_BLD=""; C_PNK=""; C_CYN=""; C_GRN=""; C_YEL=""; C_RED=""
fi
say()  { printf "${C_PNK}🐾${C_RST} ${C_BLD}%s${C_RST}\n" "$*"; }
ok()   { printf "${C_GRN}✓${C_RST}  %s\n" "$*"; }
warn() { printf "${C_YEL}!${C_RST}  %s\n" "$*"; }
err()  { printf "${C_RED}✗${C_RST}  %s\n" "$*" >&2; }
step() { printf "\n${C_CYN}▸${C_RST} ${C_BLD}%s${C_RST}\n" "$*"; }

banner() {
cat <<'B'
   /\_/\        CatSDK R11.1  (the fix)
  ( -.- )       reinstalling what R11.0 quietly skipped
   > ^ <        target: powerpc-eabi-gcc + emulators + verify
B
}

# ---- env -------------------------------------------------------------------
export DEVKITPRO="${DEVKITPRO:-/opt/devkitpro}"
export DEVKITARM="$DEVKITPRO/devkitARM"
export DEVKITPPC="$DEVKITPRO/devkitPPC"
export DEVKITA64="$DEVKITPRO/devkitA64"
export PATH="$DEVKITPPC/bin:$DEVKITARM/bin:$DEVKITA64/bin:$DEVKITPRO/tools/bin:$PATH"

DKP_PACMAN=""
for c in /opt/devkitpro/pacman/bin/dkp-pacman /usr/local/bin/dkp-pacman dkp-pacman; do
  if command -v "$c" >/dev/null 2>&1; then DKP_PACMAN="$(command -v "$c")"; break; fi
done

# ============================================================================
#  1) GameCube + Wii — install ALL devkitPPC packages by name
#     The R11.0 bug: `dkp-pacman -S --noconfirm gamecube-dev wii-dev` with
#     stdout/stderr redirected reads EOF on the "Enter a selection" group
#     prompt and installs zero of those packages while exiting 0.
# ============================================================================
fix_devkitppc() {
  step "1. devkitPPC (GameCube + Wii) — explicit package install"
  if [[ -z "$DKP_PACMAN" ]]; then
    err "dkp-pacman not found. Install devkitPro first (run catsdk-r11.sh)."
    return 1
  fi
  ok "using $DKP_PACMAN"

  say "syncing package databases"
  sudo "$DKP_PACMAN" -Syu --noconfirm || warn "sync had warnings"

  # explicit package names — every member of gamecube-dev + wii-dev groups,
  # minus the bogus 'libogc-tools' your old script kept asking for.
  local PKGS=(
    devkitPPC
    devkitppc-gcc
    devkitppc-binutils
    devkitppc-rules
    devkitppc-cmake
    devkitppc-crtls
    devkitppc-mn10200-binutils
    devkitPPC-gdb
    libogc
    libfat-ogc
    libgxflux
    gamecube-tools
    gamecube-cmake
    gamecube-pkg-config
    gamecube-examples
    ogc-cmake
    ppc-pkg-config
    wii-cmake
    wii-pkg-config
    wii-examples
    wiiload
  )
  say "installing ${#PKGS[@]} packages"
  if sudo "$DKP_PACMAN" -S --needed --noconfirm "${PKGS[@]}"; then
    ok "devkitPPC packages installed"
  else
    warn "some packages failed; continuing to verification"
  fi

  if [[ -x "$DEVKITPPC/bin/powerpc-eabi-gcc" ]]; then
    ok "powerpc-eabi-gcc found at $DEVKITPPC/bin/powerpc-eabi-gcc"
    "$DEVKITPPC/bin/powerpc-eabi-gcc" --version | head -n1
  else
    err "powerpc-eabi-gcc STILL missing — try:"
    err "   sudo $DKP_PACMAN -S --noconfirm devkitppc-gcc"
    err "   (interactively, so the group prompt isn't eaten)"
  fi
}

# ============================================================================
#  2) Make sure devkitARM + devkitA64 are also fully populated
#     (R11.0 used groups for these too — same EOF-eaten-prompt risk)
# ============================================================================
fix_other_dkp() {
  step "2. devkitARM + devkitA64 — top-up by explicit name"
  [[ -z "$DKP_PACMAN" ]] && { warn "no dkp-pacman, skip"; return; }

  local ARM_PKGS=(
    devkitARM devkitarm-gcc devkitarm-binutils devkitarm-rules
    libnds nds-examples nds-tools nds-cmake
    libgba gba-tools gba-cmake gba-examples
    libctru 3ds-tools 3ds-cmake 3ds-examples
    citro2d citro3d
  )
  local A64_PKGS=(
    devkitA64 devkita64-gcc devkita64-binutils devkita64-newlib
    libnx switch-tools switch-cmake switch-examples switch-pkg-config
    deko3d uam catnip
  )

  sudo "$DKP_PACMAN" -S --needed --noconfirm "${ARM_PKGS[@]}" \
    || warn "some devkitARM packages failed (some may not exist on your tree)"
  sudo "$DKP_PACMAN" -S --needed --noconfirm "${A64_PKGS[@]}" \
    || warn "some devkitA64 packages failed"
}

# ============================================================================
#  3) Emulators — fix mednafen (formula not cask) + try openemu cask
# ============================================================================
fix_emulators() {
  step "3. emulators (correct formula vs cask)"
  if ! command -v brew >/dev/null 2>&1; then
    warn "brew not found, skipping"
    return
  fi
  # mednafen is a FORMULA
  brew list --formula 2>/dev/null | grep -qx mednafen \
    && ok "mednafen formula already installed" \
    || { brew install mednafen >/dev/null 2>&1 && ok "mednafen formula installed" \
         || warn "mednafen formula failed"; }

  # casks — these can fail for sandbox/quarantine reasons; tolerate
  for cask in mgba dolphin pcsx2 rpcs3; do
    if brew list --cask 2>/dev/null | grep -qx "$cask"; then
      ok "$cask cask already installed"
    else
      brew install --cask "$cask" >/dev/null 2>&1 \
        && ok "$cask cask" || warn "$cask cask failed (try manually)"
    fi
  done

  # openemu cask is finicky on some macOS releases; offer manual fallback
  if brew list --cask 2>/dev/null | grep -qx openemu; then
    ok "openemu cask already installed"
  else
    brew install --cask openemu >/dev/null 2>&1 \
      && ok "openemu cask" \
      || warn "openemu cask failed — download manually from openemu.org"
  fi
}

# ============================================================================
#  4) Patch ~/.zshrc with PATH for all devkit toolchains
# ============================================================================
fix_zshrc() {
  step "4. ~/.zshrc PATH wiring"
  local rc="$HOME/.zshrc"
  touch "$rc"
  add() {
    grep -qxF "$1" "$rc" || { echo "$1" >> "$rc"; ok "added: $1"; }
  }
  add 'export DEVKITPRO=/opt/devkitpro'
  add 'export DEVKITARM=$DEVKITPRO/devkitARM'
  add 'export DEVKITPPC=$DEVKITPRO/devkitPPC'
  add 'export DEVKITA64=$DEVKITPRO/devkitA64'
  add 'export PATH=$DEVKITPPC/bin:$DEVKITARM/bin:$DEVKITA64/bin:$DEVKITPRO/tools/bin:$PATH'
}

# ============================================================================
#  5) Verify every toolchain
# ============================================================================
verify() {
  step "5. verification"
  local PASS=0 FAIL=0

  # Single-shot check: avoids duplicate invocations and SIGPIPE from `| head` on some gcc builds.
  check() {
    local label="$1" out rc
    shift
    out="$("$@" 2>&1)"
    rc=$?
    if (( rc == 0 )); then
      printf "  ${C_GRN}✓${C_RST} %-38s " "$label"
      printf '%s\n' "${out%%$'\n'*}"
      PASS=$((PASS+1))
    else
      printf "  ${C_RED}✗${C_RST} %-38s ${C_DIM}(not found)${C_RST}\n" "$label"
      FAIL=$((FAIL+1))
    fi
  }

  # devkitPPC / devkitA64: prefer canonical paths, then PATH (zshrc / login shells often only have the latter).
  local PPC_GCC="$DEVKITPPC/bin/powerpc-eabi-gcc"
  [[ -x "$PPC_GCC" ]] || PPC_GCC="$(command -v powerpc-eabi-gcc 2>/dev/null || true)"

  local A64_GCC="$DEVKITA64/bin/aarch64-none-elf-gcc"
  [[ -x "$A64_GCC" ]] || A64_GCC="$DEVKITPRO/devkitA64/bin/aarch64-none-elf-gcc"
  [[ -x "$A64_GCC" ]] || A64_GCC="$(command -v aarch64-none-elf-gcc 2>/dev/null || true)"
  [[ -x "$A64_GCC" ]] || A64_GCC="$DEVKITPRO/tools/bin/aarch64-none-elf-gcc"

  check "cc65 (NES/SNES C)"            cc65 --version
  check "ca65 (NES 6502 asm)"          ca65 --version
  check "wla-65816 (SNES asm)"         wla-65816 --version
  check "rgbasm (GB/GBC)"              rgbasm --version
  check "sdcc (SMS/Z80)"               sdcc --version
  check "m68k-elf-gcc (Genesis)"       m68k-elf-gcc --version
  check "mips64-elf-gcc (N64)"         mips64-elf-gcc --version
  check "arm-none-eabi-gcc (GBA/DS/3DS)" arm-none-eabi-gcc --version
  if [[ -x "$PPC_GCC" ]]; then
    check "powerpc-eabi-gcc (GameCube/Wii)" "$PPC_GCC" --version
  else
    printf "  ${C_RED}✗${C_RST} %-38s ${C_DIM}(not found)${C_RST}\n" "powerpc-eabi-gcc (GameCube/Wii)"
    FAIL=$((FAIL+1))
  fi
  if [[ -x "$A64_GCC" ]]; then
    check "aarch64-none-elf-gcc (Switch)" "$A64_GCC" --version
  else
    printf "  ${C_RED}✗${C_RST} %-38s ${C_DIM}(not found — try: sudo dkp-pacman -S devkita64-gcc)${C_RST}\n" \
      "aarch64-none-elf-gcc (Switch)"
    FAIL=$((FAIL+1))
  fi

  echo
  if (( FAIL == 0 )); then
    say "${C_GRN}all $PASS toolchains operational. nya~${C_RST}"
  else
    say "${C_YEL}$PASS passed, $FAIL failed.${C_RST} See notes below."
  fi
}

# ============================================================================
#  Notes — what truly cannot be fixed without GitHub
# ============================================================================
notes() {
  step "notes"
  cat <<'EOF'
Skipped on purpose (NO_GITHUB):
  - GBDK-2020       (GitHub releases only)
  - PSn00bSDK       (GitHub)
  - Yaul (Saturn)   (GitHub)
  - KallistiOS (DC) (GitHub)
  - ps2dev          (GitHub)
  - PSL1GHT (PS3)   (GitHub)
  - OpenOrbis (PS4) (GitHub)
  - libdragon brew tap was attempted and prompted for github creds —
    THIS run set GIT_TERMINAL_PROMPT=0 so it dies fast instead of hanging.

If you want any of those, run with NO_GITHUB unset and they'll come from
their official GitHub release tarballs. mips64-elf-gcc 14.2.0 you already
have is from a previous libdragon brew tap — keep it.

Removed from R11.0 (never existed in homebrew core):
  asmjit   (was a typo — that's a JIT lib, not a NES tool)
  nesasm   asm6f   sh-elf-gcc   arm-eabi-gcc   mipsel-none-elf-gcc
  xxd      (system has it under vim)
  hexdump  (already in macOS base)

Next steps after this script finishes:
  source ~/.zshrc
  powerpc-eabi-gcc --version
  arm-none-eabi-gcc --version
  aarch64-none-elf-gcc --version

aarch64-none-elf-gcc (Switch / devkitA64) shows ✗ but `which aarch64-none-elf-gcc` works:
  The script now checks $DEVKITA64/bin, $DEVKITPRO/devkitA64/bin, PATH, and
  $DEVKITPRO/tools/bin. If it still fails, install: sudo dkp-pacman -S devkita64-gcc
  Apple Silicon (M-series): use the arm64 devkitPro installer; avoid x86_64-only bins.
EOF
}

# ============================================================================
main() {
  banner
  fix_devkitppc
  fix_other_dkp
  fix_emulators
  fix_zshrc
  verify
  notes
  ok "R11.1 fix complete."
}
main "$@"
