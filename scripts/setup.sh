#!/usr/bin/env bash
# ⌘Tab HUD: install, update, develop. Asks what to do:
#
#   scripts/setup.sh
#
# or takes the answer as an argument:
#
#   install   build the app, put it in Applications in place of an older copy, start it
#   dev       debug build into build/, start it from there and follow its log
#   test      run the tests
#   restore   quit the app and give ⌘Tab back to macOS (when the app died without doing it)
#   bundle <binary> <app>   wrap a built binary into an .app (Xcode does this after each build)
#   package   the downloads, for Apple silicon and Intel: build/release/CmdTabWheel.dmg and .zip
#   release   publish the pushed main as a GitHub release: tags it, GitHub builds and uploads it
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"

EXECUTABLE="CmdTabWheel"
APP_NAME="⌘Tab HUD.app" # the file's name is what Finder and System Settings show
OLD_APP_NAME="$EXECUTABLE.app" # its name up to v22: a copy under it gets replaced
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

fail() {
  echo "✗ $*" >&2
  exit 1
}

menu() {
  echo "⌘Tab HUD"
  echo "  1) Install or update: build it, put it in Applications, start it"
  echo "  2) Develop: a debug build from build/, with its log in this window"
  echo "  3) Run the tests"
  echo "  4) Quit it and give ⌘Tab back to macOS"
  while true; do
    read -r -p "What to do? [1] " choice || exit 1 # Ctrl+D
    case "${choice:-1}" in
      1) install_app; return ;;
      2) run_dev; return ;;
      3) run_tests; return ;;
      4) restore_switcher; return ;;
    esac
  done
}

# MARK: - Install or update

# A copy already in /Applications or ~/Applications is replaced where it is. Otherwise the app
# goes to /Applications, or to ~/Applications for a user who can't write there.
install_app() {
  check_tools
  local old dest stage="build/setup" status
  old="$(installed_copy)"
  if [ -n "$old" ]; then
    dest="$(dirname "$old")/$APP_NAME"
  elif [ -w /Applications ]; then
    dest="/Applications/$APP_NAME"
  else
    dest="$HOME/Applications/$APP_NAME"
  fi

  echo "▸ swift build (release)"
  swift build -c release
  rm -rf "$stage"
  bundle_app "$(swift build -c release --show-bin-path)/$EXECUTABLE" "$stage/$APP_NAME"
  "$LSREGISTER" -u "$stage/$APP_NAME" # only the installed copy should be known to the system

  stop_running "$stage/$APP_NAME"
  if [ -n "$old" ]; then
    echo "▸ replacing $old"
    # The old copy is moved out (and deleted along with $stage below), not deleted in place:
    # if the new one can't get in, the old one goes back.
    if ! mv "$old" "$stage/old-$APP_NAME"; then
      open "$old" # it was quit above
      fail "couldn't move the old $old out of the way.
  If macOS said your terminal was prevented from modifying apps: System Settings → Privacy & Security
  → App Management → turn your terminal on, then run this again. Or drag $ROOT/$stage/$APP_NAME
  into Applications in Finder yourself."
    fi
    if ! mv "$stage/$APP_NAME" "$dest"; then
      mv "$stage/old-$APP_NAME" "$old"
      open "$old"
      fail "couldn't put the new app into $(dirname "$dest"); the old one is back and running"
    fi
    status="updated"
  else
    echo "▸ installing into $(dirname "$dest")"
    mkdir -p "$(dirname "$dest")"
    mv "$stage/$APP_NAME" "$dest"
    status="installed"
  fi
  rm -rf "$stage" || echo "⚠︎ couldn't delete the old copy in $stage: the new one is installed anyway" >&2
  "$LSREGISTER" -f "$dest"

  open "$dest"
  echo "✓ ⌘Tab HUD $(version_of "$dest") $status: $dest"
  if [ "$status" = "installed" ]; then
    echo "  It's in the menu bar now; its setup window asks for the permissions it needs."
  fi
}

# MARK: - Develop

# Debug build → build/⌘Tab HUD.app (where Xcode's ⌘R puts it too) → start it → follow its log.
# Ctrl+C stops following the log; the app keeps running (quit it from the menu bar icon).
run_dev() {
  check_tools
  echo "▸ swift build (debug)"
  swift build
  bundle_app "$(swift build --show-bin-path)/$EXECUTABLE" "build/$APP_NAME"
  stop_running "build/$APP_NAME"
  open "build/$APP_NAME"
  echo "▸ its log (Ctrl+C to stop following it)"
  exec /usr/bin/log stream --style compact --level info \
    --predicate 'subsystem == "com.faustienf.CmdTabWheel"'
}

# MARK: - Test

run_tests() {
  check_tools
  echo "▸ swift test"
  swift test
}

# MARK: - Release

# What people download: one binary for Apple silicon and Intel, ad-hoc signed (there's no
# Developer ID), in build/release/: CmdTabWheel.dmg to drag into Applications from a browser,
# CmdTabWheel.zip for scripts/download.sh. $1, if given: the version it must be ("v18"), so a
# release can't go out under the wrong number.
package_app() {
  check_tools
  local out="build/release" bin
  echo "▸ swift build (release, Apple silicon and Intel)"
  swift build -c release --arch arm64 --arch x86_64
  bin="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/$EXECUTABLE"
  rm -rf "$out"
  SIGN_IDENTITY=- bundle_app "$bin" "$out/$APP_NAME"
  "$LSREGISTER" -u "$out/$APP_NAME" # only the installed copy should be known to the system

  local app="$out/$APP_NAME" version
  version="v$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
  [ -z "${1:-}" ] || [ "$1" = "$version" ] || fail "the app is $version, not $1"
  local archs
  archs="$(lipo -archs "$app/Contents/MacOS/$EXECUTABLE")"
  [[ "$archs" == *arm64* && "$archs" == *x86_64* ]] || fail "not for both Apple silicon and Intel: $archs"
  [ -f "$app/Contents/Resources/Assets.car" ] || fail "no icon in the app (actool needs Xcode)"
  # Without extended attributes: `unzip` would turn them into ._ files that break the signature.
  ditto -c -k --norsrc --noextattr --noacl --keepParent "$app" "$out/$EXECUTABLE.zip"

  local dmgbuild
  dmgbuild="$(dmgbuild_tool)"
  echo "▸ drawing the DMG window"
  swift scripts/draw-dmg-background.swift "$out/dmg-background.tiff"
  "$dmgbuild" -s scripts/dmg-settings.py -D app="$app" -D background="$out/dmg-background.tiff" \
    "⌘Tab HUD $version" "$out/$EXECUTABLE.dmg" >/dev/null
  echo "✓ $out/$EXECUTABLE.dmg and .zip: ⌘Tab HUD $(version_of "$app")"
}

# dmgbuild lays out the DMG window without Finder, so it works on CI too. It's a Python tool:
# it goes into a virtualenv in build/, downloaded on first use.
DMGBUILD=(dmgbuild==1.6.7 ds_store==1.3.3 mac_alias==2.2.3)
dmgbuild_tool() {
  local venv="$ROOT/build/dmgbuild" python
  if [ ! -x "$venv/bin/python" ]; then
    for python in python3 python3.14 python3.13 python3.12 python3.11 python3.10 \
                  /opt/homebrew/bin/python3 /usr/local/bin/python3 ""; do
      [ -n "$python" ] || fail "the DMG needs Python 3.10 or later: brew install python"
      "$python" -c 'import sys; sys.exit(sys.version_info < (3, 10))' 2>/dev/null && break
    done
    echo "▸ setting up dmgbuild in $venv" >&2
    "$python" -m venv "$venv" >&2
  fi
  "$venv/bin/python" -m pip install --quiet --disable-pip-version-check "${DMGBUILD[@]}" >&2 \
    || fail "couldn't install dmgbuild"
  echo "$venv/bin/dmgbuild"
}

# Tags what's on GitHub's main with the version number and pushes the tag; GitHub Actions
# (.github/workflows/release.yml) builds it with `package` and publishes the release.
release() {
  [ -z "$(git status --porcelain)" ] || fail "commit your changes first: a release is built from GitHub"
  git fetch --quiet origin main
  git merge-base --is-ancestor HEAD origin/main || fail "push main first: a release is built from GitHub"
  local tag
  tag="v$(version_number)"
  ! git rev-parse --quiet --verify "refs/tags/$tag" >/dev/null || fail "$tag is out already"
  git tag --annotate "$tag" --message "⌘Tab HUD $tag"
  git push --quiet origin "refs/tags/$tag"
  local repo
  repo="$(git remote get-url origin | sed -E 's#^(git@github\.com:|https://github\.com/)##; s#\.git$##')"
  echo "✓ $tag pushed. GitHub builds and publishes it in a few minutes:"
  echo "  https://github.com/$repo/actions"
  echo "  https://github.com/$repo/releases/tag/$tag"
}

# MARK: - Give ⌘Tab back

restore_switcher() {
  local app
  for app in "$(installed_copy)" "build/$APP_NAME"; do
    [ -x "$app/Contents/MacOS/$EXECUTABLE" ] || continue
    stop_running "$app" # quitting gives ⌘Tab back by itself; this covers a crashed app
    "$app/Contents/MacOS/$EXECUTABLE" --restore-native-switcher
    echo "✓ ⌘Tab is the system switcher again"
    return
  done
  fail "no built app to do it with: install it first"
}

# MARK: - Parts

check_tools() {
  [ "$(id -u)" -ne 0 ] || fail "run it without sudo"
  [ "$(sw_vers -productVersion | cut -d. -f1)" -ge 14 ] || fail "⌘Tab HUD needs macOS 14 or later"
  use_xcode
  xcrun --find swift >/dev/null 2>&1 \
    || fail "no Swift here: install Xcode 16 or later from the App Store, open it once, then run this again"
}

# Xcode's tools even when the Command Line Tools are the selected ones (xcode-select): every
# command builds with the same Swift, and only Xcode has Swift Testing. The two Swifts can
# disagree about what compiles, so building with one and testing with the other hides errors.
use_xcode() {
  if xcode-select -p 2>/dev/null | grep -q CommandLineTools && [ -d /Applications/Xcode.app ]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
  fi
}

# The copy in /Applications or ~/Applications, under the app's name or its old one; nothing if
# there's none.
installed_copy() {
  local folder name
  for folder in /Applications "$HOME/Applications"; do
    for name in "$APP_NAME" "$OLD_APP_NAME"; do
      if [ -d "$folder/$name" ]; then
        echo "$folder/$name"
        return
      fi
    done
  done
}

# Quits every running copy, whatever folder it runs from. Two copies would fight over ⌘Tab, and
# `open` only brings a running copy forward: it doesn't start a newer one from somewhere else.
# $1: an app whose binary can give ⌘Tab back to macOS if a copy has to be killed.
stop_running() {
  local user_id
  user_id="$(id -u)"
  # SIGTERM = graceful quit: the app gives the system ⌘Tab back before exiting.
  pkill -x -U "$user_id" "$EXECUTABLE" || return 0 # nothing running
  echo "▸ quitting the running ⌘Tab HUD"
  for _ in $(seq 30); do
    pgrep -x -U "$user_id" "$EXECUTABLE" >/dev/null || return 0
    sleep 0.1
  done
  # Still alive → it runs under Xcode's debugger, which swallows SIGTERM.
  # Force it, and give ⌘Tab back on its behalf.
  pkill -9 -x -U "$user_id" "$EXECUTABLE" || true
  sleep 0.3
  "$1/Contents/MacOS/$EXECUTABLE" --restore-native-switcher
}

# The version: a number that grows by one with every commit (the commit count plus 2, so it
# started at 13), and the commit it was built from — "d97685b, modified" when what goes into the
# app has uncommitted changes. The app shows it in About and writes it to its log.
stamp_version() {
  local plist="$1" number=0 commit="unknown"
  if git -C "$ROOT" rev-parse --git-dir >/dev/null 2>&1; then
    if [ "$(git -C "$ROOT" rev-parse --is-shallow-repository)" = true ]; then
      echo "⚠︎ no version number: a shallow clone has no history to count (git fetch --unshallow)" >&2
    else
      number="$(version_number)"
    fi
    commit="$(git -C "$ROOT" rev-parse --short HEAD)"
    if [ -n "$(git -C "$ROOT" status --porcelain -- Sources Support Package.swift)" ]; then
      commit="$commit, modified"
    fi
  fi
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $number" -c "Set :CFBundleVersion $number" \
    -c "Add :GitCommit string $commit" "$plist"
}

version_number() {
  echo $(($(git -C "$ROOT" rev-list --count HEAD) + 2))
}

# The version an app was stamped with, "v13 (d97685b)".
version_of() {
  local plist="$1/Contents/Info.plist"
  echo "v$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")" \
    "($(/usr/libexec/PlistBuddy -c 'Print :GitCommit' "$plist"))"
}

# Wraps a built binary into an .app and signs it. An .app is just a folder:
#   ⌘Tab HUD.app/Contents/Info.plist        ← bundle id, LSUIElement, version…
#   ⌘Tab HUD.app/Contents/MacOS/CmdTabWheel ← the binary
#   ⌘Tab HUD.app/Contents/Resources/        ← the icon: Assets.car (macOS 26 glass icon
#                                              and older systems) + AppIcon.icns (fallback)
bundle_app() {
  local bin="$1" app="$2"
  local info_plist="$ROOT/Support/Info.plist"
  local bundle_id
  bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$info_plist")"

  # The icon's source is Support/AppIcon.icon (Icon Composer). actool compiles it; the result is
  # cached in build/icon and redone only when the source changes.
  local icon_source="$ROOT/Support/AppIcon.icon" icon_cache="$ROOT/build/icon"
  if [ ! -f "$icon_cache/Assets.car" ] || [ -n "$(find "$icon_source" -newer "$icon_cache/Assets.car")" ]; then
    # actool comes with Xcode, not the Command Line Tools — use Xcode even if it isn't selected.
    if ! xcrun --find actool >/dev/null 2>&1 && [ -d /Applications/Xcode.app ]; then
      export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
    fi
    echo "▸ compiling the app icon"
    rm -rf "$icon_cache"
    mkdir -p "$icon_cache"
    if ! xcrun actool "$icon_source" --compile "$icon_cache" --app-icon AppIcon \
        --platform macosx --minimum-deployment-target 14.0 \
        --output-partial-info-plist "$icon_cache/partial.plist" >/dev/null; then
      rm -rf "$icon_cache"
      echo "⚠︎ no icon: actool failed (it needs Xcode)" >&2
    fi
  fi

  echo "▸ assembling $app"
  rm -rf "$app"
  # One built here under the old name goes: Launch Services could show that one instead.
  local old
  old="$(dirname "$app")/$OLD_APP_NAME"
  if [ -d "$old" ]; then
    "$LSREGISTER" -u "$old"
    rm -rf "$old"
  fi
  mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
  cp "$bin" "$app/Contents/MacOS/$EXECUTABLE"
  cp "$info_plist" "$app/Contents/Info.plist"
  stamp_version "$app/Contents/Info.plist"
  if [ -f "$icon_cache/Assets.car" ]; then
    cp "$icon_cache/Assets.car" "$icon_cache/AppIcon.icns" "$app/Contents/Resources/"
  fi

  # Use a real certificate if there is one (SIGN_IDENTITY overrides), else ad-hoc ("-").
  local identity="${SIGN_IDENTITY:-$(security find-identity -v -p codesigning \
    | awk -F'"' '/Apple Development|Developer ID Application/ { print $2; exit }')}"
  identity="${identity:--}"

  echo "▸ codesign with: $identity"
  if [ "$identity" = "-" ]; then
    # Ad-hoc signatures identify the app by its binary hash, which changes on every build,
    # so macOS forgets the Accessibility permission after each rebuild. Pin the designated
    # requirement to the bundle id instead — the permission then survives rebuilds.
    # Dev-only trade-off: any ad-hoc app claiming this bundle id would match too.
    codesign --force --sign - --requirements "=designated => identifier \"$bundle_id\"" "$app"
  else
    codesign --force --sign "$identity" "$app"
  fi
  codesign --verify --strict "$app"
  # Tell Launch Services about the new bundle right away, so Finder, the Dock and System Settings
  # show the current icon instead of a cached (or missing) one.
  "$LSREGISTER" -f "$app"
  echo "✓ $app, $(version_of "$app")"
}

case "${1:-}" in
  "") if [ -t 0 ]; then menu; else install_app; fi ;;
  install) install_app ;;
  dev) run_dev ;;
  test) run_tests ;;
  restore) restore_switcher ;;
  bundle)
    [ $# -eq 3 ] || fail "usage: scripts/setup.sh bundle <binary> <output.app>"
    bundle_app "$2" "$3"
    ;;
  package) package_app "${2:-}" ;;
  release) release ;;
  *) fail "unknown command: $1 (there are install, dev, test, restore, package, release)" ;;
esac
