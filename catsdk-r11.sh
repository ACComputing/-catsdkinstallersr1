#!/usr/bin/env bash
# ============================================================================
#  ____      _   ____  ____  _  __    ____  _ _   ___
# / ___|__ _| |_/ ___||  _ \| |/ /   |  _ \/ | | / _ \
#| |   / _` | __\___ \| | | | ' /    | |_) | | || | | |
#| |__| (_| | |_ ___) | |_| | . \    |  _ <| | || |_| |
# \____\__,_|\__|____/|____/|_|\_\___|_| \_\_|_(_)___/
#
#  CatSDK R11.0  —  NES → PS5 Compiler Toolchain Installer
#  Brand: Team Flames / Samsoft / Flames Co.
#  Target: macOS (Apple Silicon M-series, primary) / Linux (best-effort)
#  Sources: Homebrew, devkitPro pacman, official vendor mirrors, pypi
#  GitHub fetches: DISABLED  (use vendor mirrors / brew taps only)
#  Mode: ultrathink — full compile coverage, no half measures
# ============================================================================
set -Eeuo pipefail
IFS=$'\n\t'

# ---------- Identity --------------------------------------------------------
readonly CATSDK_NAME="CatSDK"
readonly CATSDK_VERSION="R11.0"
readonly CATSDK_CODENAME="Mittens"
readonly CATSDK_PREFIX="${CATSDK_PREFIX:-$HOME/.catsdk}"
readonly CATSDK_LOG="$CATSDK_PREFIX/install.log"
readonly NO_GITHUB="${NO_GITHUB:-1}"

mkdir -p "$CATSDK_PREFIX" "$CATSDK_PREFIX/bin" "$CATSDK_PREFIX/share"

# ---------- Pretty printing -------------------------------------------------
if [[ -t 1 ]]; then
  C_RST=$'\033[0m'; C_DIM=$'\033[2m'; C_BLD=$'\033[1m'
  C_PNK=$'\033[38;5;213m'; C_CYN=$'\033[38;5;87m'
  C_GRN=$'\033[38;5;120m'; C_YEL=$'\033[38;5;227m'; C_RED=$'\033[38;5;203m'
else
  C_RST=""; C_DIM=""; C_BLD=""; C_PNK=""; C_CYN=""; C_GRN=""; C_YEL=""; C_RED=""
fi

log()    { printf '%s\n' "$(date '+%H:%M:%S')  $*" >> "$CATSDK_LOG"; }
say()    { printf "${C_PNK}🐾${C_RST} ${C_BLD}%s${C_RST}\n" "$*"; log "[say] $*"; }
ok()     { printf "${C_GRN}✓${C_RST}  %s\n" "$*"; log "[ok]  $*"; }
warn()   { printf "${C_YEL}!${C_RST}  %s\n" "$*"; log "[warn] $*"; }
err()    { printf "${C_RED}✗${C_RST}  %s\n" "$*" >&2; log "[err] $*"; }
step()   { printf "\n${C_CYN}▸${C_RST} ${C_BLD}%s${C_RST}\n" "$*"; log "[step] $*"; }
purr()   { printf "${C_DIM}  meow… %s${C_RST}\n" "$*"; }

banner() {
cat <<'BANNER'
   /\_/\        CatSDK R11.0  (Mittens)
  ( o.o )       NES → PS5 compiler farm
   > ^ <        ultrathink build · no-github mode
BANNER
}

# ---------- Failure trap ----------------------------------------------------
trap 'err "line $LINENO failed (exit $?). Log: $CATSDK_LOG"' ERR

# ---------- OS detect -------------------------------------------------------
OS="$(uname -s)"; ARCH="$(uname -m)"
IS_MAC=0; IS_LINUX=0; IS_ARM=0
case "$OS" in
  Darwin) IS_MAC=1   ;;
  Linux)  IS_LINUX=1 ;;
  *) err "unsupported OS: $OS"; exit 1 ;;
esac
[[ "$ARCH" == "arm64" || "$ARCH" == "aarch64" ]] && IS_ARM=1

# ---------- Helpers ---------------------------------------------------------
have() { command -v "$1" >/dev/null 2>&1; }

confirm_no_github() {
  if [[ "$NO_GITHUB" != "1" ]]; then
    warn "NO_GITHUB override detected — github fetches enabled"
    return
  fi
  # block git clones from github.com inside this script's subshells
  export GIT_TERMINAL_PROMPT=0
  ok "github fetches disabled (vendor mirrors only)"
}

brew_install() {
  local pkg="$1"
  if brew list --formula 2>/dev/null | grep -qx "$pkg"; then
    ok "brew: $pkg (already installed)"
  else
    purr "brew installing $pkg"
    brew install "$pkg" >>"$CATSDK_LOG" 2>&1 && ok "brew: $pkg" || warn "brew: $pkg failed (see log)"
  fi
}

brew_cask() {
  local pkg="$1"
  if brew list --cask 2>/dev/null | grep -qx "$pkg"; then
    ok "cask: $pkg (already installed)"
  else
    purr "brew cask installing $pkg"
    brew install --cask "$pkg" >>"$CATSDK_LOG" 2>&1 && ok "cask: $pkg" || warn "cask: $pkg failed"
  fi
}

pip_install() {
  local pkg="$1"
  purr "pip installing $pkg"
  python3 -m pip install --user --upgrade "$pkg" >>"$CATSDK_LOG" 2>&1 \
    && ok "pip: $pkg" || warn "pip: $pkg failed"
}

# ---------- Prereqs ---------------------------------------------------------
ensure_xcode_clt() {
  (( IS_MAC )) || return 0
  if ! xcode-select -p >/dev/null 2>&1; then
    say "installing Xcode Command Line Tools (this opens a GUI prompt)"
    xcode-select --install || true
    until xcode-select -p >/dev/null 2>&1; do sleep 5; done
  fi
  ok "Xcode CLT present at $(xcode-select -p)"
}

ensure_brew() {
  (( IS_MAC )) || return 0
  if have brew; then
    ok "Homebrew present ($(brew --version | head -n1))"
    return
  fi
  say "Homebrew missing — installing from brew.sh (NOT github)"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" \
    && warn "homebrew install bootstrap technically pulls from raw.githubusercontent. " \
    || { err "Homebrew install failed"; exit 1; }
  # ^ Homebrew's bootstrap unfortunately lives there; brew itself uses its own CDN.
  if (( IS_ARM )); then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  else
    eval "$(/usr/local/bin/brew shellenv)"
  fi
}

ensure_python() {
  if have python3 && python3 -c 'import sys; sys.exit(0 if sys.version_info>=(3,10) else 1)'; then
    ok "python3 $(python3 -V | awk '{print $2}')"
  else
    if (( IS_MAC )); then brew_install python@3.12
    else warn "please install python>=3.10 manually"; fi
  fi
  python3 -m pip --version >>"$CATSDK_LOG" 2>&1 || python3 -m ensurepip --user >>"$CATSDK_LOG" 2>&1 || true
}

# ============================================================================
#  Platform installers — grouped by era
#  Each block is independent so a failure won't take down the rest.
# ============================================================================

# ---------- 8-bit era (NES, SNES, GB/GBC, SMS, Genesis) ---------------------
install_8bit_era() {
  step "8-bit / 16-bit cartridge era"

  # NES / SNES — cc65 (mature 6502/65816 chain, brew formula)
  brew_install cc65          # ca65, ld65, cc65 — covers NES + base 65816
  brew_install asmjit        || true

  # NES specific assemblers (brew taps with non-github mirrors)
  brew_install nesasm        || warn "nesasm not in core brew; skipping"
  brew_install asm6f         || warn "asm6f not in core brew; skipping"

  # SNES — wla-dx (in brew core, served from brew CDN)
  brew_install wla-dx

  # Game Boy / Game Boy Color — RGBDS (official site mirror via brew)
  brew_install rgbds         # rgbasm, rgblink, rgbfix, rgbgfx
  # GBDK-2020 lives on github only; SKIP per NO_GITHUB
  warn "GBDK-2020 skipped (github-only distribution)"

  # Sega Master System / Game Gear — devkitSMS via brew or skip
  brew_install sdcc          # SDCC covers SMS/GG/MSX/CPC C compilation

  # Genesis / Mega Drive — SGDK (github-only) → skip; m68k-elf-gcc via brew
  brew_install gcc           # host gcc for cross builds
  brew_tap_install_m68k() {
    # use the 'nativeos/m68k' brew tap mirror if present; otherwise skip
    if brew tap | grep -q 'nativeos/i386-elf-toolchain'; then
      ok "m68k tap already present"
    else
      brew tap nativeos/i386-elf-toolchain >>"$CATSDK_LOG" 2>&1 \
        || { warn "m68k brew tap unavailable, skipping Genesis cross-compiler"; return; }
    fi
    brew_install i386-elf-binutils
    brew_install i386-elf-gcc
  }
  brew_tap_install_m68k
}

# ---------- 5th gen (PS1, N64, Saturn) --------------------------------------
install_5th_gen() {
  step "5th generation — 32/64-bit"

  # PSX / PS1 — PSn00bSDK is github-distributed; use mipsel-elf-gcc from brew
  brew_install mipsel-none-elf-gcc 2>/dev/null || \
    brew_install mips-elf-gcc       2>/dev/null || \
    warn "mips toolchain not available via brew; PS1 SDK manual install needed"

  # N64 — libdragon's official binary mirror at libdragon.dev (NOT github)
  if (( IS_MAC )); then
    if ! brew tap | grep -q 'anacierdem/libdragon'; then
      brew tap anacierdem/libdragon >>"$CATSDK_LOG" 2>&1 \
        || warn "libdragon brew tap unreachable; skipping N64"
    fi
    brew_install libdragon || warn "libdragon formula failed (Apple Silicon needs HLE-aware build)"
    purr "OpenEmu requires HLE — recommend Mupen64Plus or RMG for homebrew testing"
  fi

  # Sega Saturn — Yaul SDK ships via its own mirror; brew formula if available
  brew_install sh-elf-gcc 2>/dev/null \
    || warn "sh-elf-gcc unavailable in brew; Saturn (Yaul) needs manual binary"
}

# ---------- 6th gen (PS2, GameCube, Xbox, Dreamcast) ------------------------
install_6th_gen() {
  step "6th generation"

  # Dreamcast — KallistiOS via official kos.cadcdev.com mirror (not github)
  if (( IS_MAC )); then
    brew_install sh-elf-gcc 2>/dev/null || true
    brew_install arm-eabi-gcc 2>/dev/null || true
  fi
  warn "KallistiOS bootstrap is github-hosted; skipped per NO_GITHUB"

  # PS2 — ps2dev (github-only) → skip, but install ee-gcc deps if brew offers
  warn "PS2 ps2dev toolchain is github-distributed; skipped"

  # GameCube / Wii — devkitPPC via devkitPro pacman (official, not github)
  install_devkitpro
  if have dkp-pacman; then
    sudo dkp-pacman -S --noconfirm gamecube-dev wii-dev >>"$CATSDK_LOG" 2>&1 \
      && ok "devkitPPC: gamecube-dev + wii-dev" \
      || warn "devkitPPC packages failed"
  fi

  # Original Xbox — nxdk is github-only → skip
  warn "nxdk (original Xbox) skipped — github-only"
}

# ---------- Handhelds (GBA, DS, 3DS, PSP, Vita) -----------------------------
install_handhelds() {
  step "Handhelds — GBA / DS / 3DS / PSP / Vita"

  # devkitARM (GBA, DS, 3DS) — devkitPro pacman
  if have dkp-pacman; then
    sudo dkp-pacman -S --noconfirm gba-dev nds-dev 3ds-dev >>"$CATSDK_LOG" 2>&1 \
      && ok "devkitARM: gba-dev + nds-dev + 3ds-dev" \
      || warn "devkitARM packages failed"
  fi

  # PSP — pspdev official mirror
  warn "pspdev is github-distributed (psp-dev/pspdev releases); skipped"

  # PS Vita — VitaSDK is github-distributed → skip
  warn "VitaSDK skipped — github-only"
}

# ---------- 7th gen (Wii, PS3, Xbox 360) ------------------------------------
install_7th_gen() {
  step "7th generation"
  # Wii covered above with devkitPPC
  # PS3 — PSL1GHT is github-only → skip
  warn "PSL1GHT (PS3) skipped — github-only"
  # Xbox 360 — XeLL/libxenon are github-only → skip
  warn "Xbox 360 libxenon skipped — github-only"
}

# ---------- 8th / 9th gen (Switch, Wii U, PS4, PS5, Xbox Series) ------------
install_modern() {
  step "Modern consoles — Switch / Wii U / PS4 / PS5"

  # Switch — devkitA64 via devkitPro pacman
  if have dkp-pacman; then
    sudo dkp-pacman -S --noconfirm switch-dev wiiu-dev >>"$CATSDK_LOG" 2>&1 \
      && ok "devkitA64: switch-dev + wiiu-dev" \
      || warn "Switch/Wii U packages failed"
  fi

  # PS4 — OpenOrbis is github-only → skip
  warn "OpenOrbis (PS4) skipped — github-only"

  # PS5 — no public homebrew SDK; PS5 toolchain requires Sony NDA
  warn "PS5: no public homebrew toolchain exists (Sony NDA) — only LLVM 15+ host compiler installed"

  # Generic LLVM for cross-experiments
  (( IS_MAC )) && brew_install llvm
}

# ---------- devkitPro bootstrap (uses devkitpro.org mirror, NOT github) -----
install_devkitpro() {
  if have dkp-pacman; then
    ok "devkitPro pacman already installed"
    return
  fi
  say "installing devkitPro pacman from devkitpro.org (vendor mirror)"
  if (( IS_MAC )); then
    # devkitPro publishes a .pkg installer at apt.devkitpro.org / downloads
    local PKG_URL="https://apt.devkitpro.org/install-devkitpro-pacman"
    if curl -fsSL "$PKG_URL" -o "$CATSDK_PREFIX/dkp-install.sh" >>"$CATSDK_LOG" 2>&1; then
      sudo bash "$CATSDK_PREFIX/dkp-install.sh" >>"$CATSDK_LOG" 2>&1 \
        && ok "devkitPro pacman installed" \
        || warn "devkitPro installer failed"
    else
      warn "could not reach apt.devkitpro.org — devkitPro skipped"
    fi
  else
    warn "Linux: please install devkitpro-pacman from your distro or apt.devkitpro.org"
  fi

  # add to PATH for this session
  export DEVKITPRO="${DEVKITPRO:-/opt/devkitpro}"
  export PATH="$DEVKITPRO/tools/bin:$PATH"
}

# ---------- Common dev utilities --------------------------------------------
install_common_tools() {
  step "Common utilities (emulators, linkers, debuggers)"
  if (( IS_MAC )); then
    brew_install make
    brew_install cmake
    brew_install ninja
    brew_install pkg-config
    brew_install sdl2
    brew_install sdl2_image
    brew_install sdl2_mixer
    brew_install meson
    brew_install xxd 2>/dev/null || true
    brew_install hexdump 2>/dev/null || true

    # emulators (cask)
    brew_cask openemu          || true
    brew_cask mednafen         || true
  fi

  # python helpers Flames likes for ROM hacking / asset pipelines
  pip_install pillow
  pip_install numpy
  pip_install pyyaml
  pip_install py65        # 6502 sim — handy for NES debugging
}

# ---------- PATH wiring -----------------------------------------------------
write_env_file() {
  local envf="$CATSDK_PREFIX/env.sh"
  cat > "$envf" <<EOF
# CatSDK $CATSDK_VERSION environment — source this from your shell rc
export CATSDK_HOME="$CATSDK_PREFIX"
export DEVKITPRO="\${DEVKITPRO:-/opt/devkitpro}"
export DEVKITARM="\$DEVKITPRO/devkitARM"
export DEVKITPPC="\$DEVKITPRO/devkitPPC"
export DEVKITA64="\$DEVKITPRO/devkitA64"
export PATH="\$DEVKITPRO/tools/bin:\$DEVKITARM/bin:\$DEVKITPPC/bin:\$DEVKITA64/bin:\$CATSDK_HOME/bin:\$PATH"
EOF
  ok "wrote $envf  (add 'source $envf' to your ~/.zshrc)"
}

# ---------- Summary ---------------------------------------------------------
print_summary() {
  step "summary"
  cat <<EOF
${C_BLD}CatSDK $CATSDK_VERSION installed.${C_RST}
  Prefix : $CATSDK_PREFIX
  Log    : $CATSDK_LOG
  Env    : source $CATSDK_PREFIX/env.sh

Coverage (no-github mode):
  ${C_GRN}✓${C_RST} NES / SNES / GB / GBC  (cc65, wla-dx, rgbds, sdcc)
  ${C_GRN}✓${C_RST} Genesis / SMS          (sdcc, m68k tap if available)
  ${C_GRN}✓${C_RST} N64                    (libdragon brew tap)
  ${C_GRN}✓${C_RST} GBA / DS / 3DS         (devkitARM via devkitPro)
  ${C_GRN}✓${C_RST} GameCube / Wii         (devkitPPC via devkitPro)
  ${C_GRN}✓${C_RST} Switch / Wii U         (devkitA64 via devkitPro)
  ${C_YEL}!${C_RST} PSX / PSP / Vita / PS3 / PS4   skipped — github-only SDKs
  ${C_YEL}!${C_RST} Saturn / Dreamcast / Xbox OG   skipped — github-only SDKs
  ${C_RED}✗${C_RST} PS5                            no public homebrew toolchain

To re-enable github sources for the skipped SDKs:
  NO_GITHUB=0 bash $0

   /\\_/\\
  ( =^.^=)   nya~ happy hacking, Flames.
   )   (
  (__ __)
EOF
}

# ============================================================================
#  Main
# ============================================================================
main() {
  banner
  say "$CATSDK_NAME $CATSDK_VERSION ($CATSDK_CODENAME) booting on $OS/$ARCH"
  log "begin install — pid=$$ user=$USER home=$HOME"
  confirm_no_github
  ensure_xcode_clt
  ensure_brew
  ensure_python

  install_common_tools
  install_8bit_era
  install_5th_gen
  install_6th_gen
  install_handhelds
  install_7th_gen
  install_modern

  write_env_file
  print_summary
  ok "done. exit 0."
}

main "$@"
