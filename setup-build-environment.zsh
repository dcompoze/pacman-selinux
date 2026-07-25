#!/usr/bin/env zsh

emulate -L zsh
setopt NO_UNSET PIPE_FAIL

typeset -gr SCRIPT_DIR=${0:A:h}
source "$SCRIPT_DIR/release-common.zsh"

parse_prompt_option "$@" || exit $?

if (( EUID != 0 ))
then
  print -u2 -r -- "ERROR This script must run as root"
  exit 1
fi

if [[ ! -r /etc/os-release ]] ||
  ! grep -Eq '^ID=(arch|"arch")$' /etc/os-release
then
  print -u2 -r -- "ERROR The build environment must be Arch Linux"
  exit 1
fi

if [[ $(uname -m) != x86_64 ]]
then
  print -u2 -r -- "ERROR The build environment must be x86_64"
  exit 1
fi

if grep -Eq '^[[:space:]]*\[selinux\][[:space:]]*$' /etc/pacman.conf
then
  print -u2 -r -- \
    "ERROR Do not configure the selinux repository inside the build container"
  exit 1
fi

typeset command

for command in pacman useradd install
do
  if ! command -v "$command" >/dev/null 2>&1
  then
    print -u2 -r -- "ERROR Required command is missing: $command"
    exit 1
  fi
done

if (( PROMPT_ENABLED ))
then
  confirm_action \
    "Update Arch and configure the disposable package-build environment?" ||
    exit $?
fi

if ! pacman -Syu --needed --noconfirm \
  archlinux-keyring base-devel git gnupg jq sudo zsh
then
  print -u2 -r -- "ERROR Could not install build-environment packages"
  exit 1
fi

if ! command -v visudo >/dev/null 2>&1
then
  print -u2 -r -- "ERROR visudo is unavailable after installing sudo"
  exit 1
fi

typeset -gr BUILD_USER=pacman-build
typeset -gr BUILD_HOME=/var/lib/pacman-build

if id "$BUILD_USER" >/dev/null 2>&1
then
  if [[ $(id -u "$BUILD_USER") == 0 ]]
  then
    print -u2 -r -- "ERROR Build user must not be root"
    exit 1
  fi
else
  if ! useradd --create-home --user-group --home-dir "$BUILD_HOME" \
    --shell /bin/bash "$BUILD_USER"
  then
    print -u2 -r -- "ERROR Could not create build user"
    exit 1
  fi
fi

typeset build_group
build_group=$(id -gn "$BUILD_USER")

if ! install -d -m 0755 -o "$BUILD_USER" -g "$build_group" \
  "$BUILD_HOME" "$BUILD_ROOT"
then
  print -u2 -r -- "ERROR Could not prepare build directories"
  exit 1
fi

typeset -gr SUDOERS_FILE=/etc/sudoers.d/pacman-build
typeset temporary_sudoers

temporary_sudoers=$(mktemp /etc/sudoers.d/pacman-build.XXXXXX) ||
  exit 1

if ! print -r -- \
  "$BUILD_USER ALL=(root) NOPASSWD: /usr/bin/pacman" > "$temporary_sudoers"
then
  rm -f -- "$temporary_sudoers"
  print -u2 -r -- "ERROR Could not write build-user sudo policy"
  exit 1
fi

chmod 0440 "$temporary_sudoers"

if ! visudo -cf "$temporary_sudoers" >/dev/null
then
  rm -f -- "$temporary_sudoers"
  print -u2 -r -- "ERROR Build-user sudo policy is invalid"
  exit 1
fi

if ! mv -f -- "$temporary_sudoers" "$SUDOERS_FILE"
then
  rm -f -- "$temporary_sudoers"
  print -u2 -r -- "ERROR Could not install build-user sudo policy"
  exit 1
fi

typeset -gr SOURCE_KEYSERVER=${PACMAN_GPG_KEYSERVER:-hkps://keyserver.ubuntu.com}
typeset -A source_keys
typeset srcinfo_file
typeset key_fingerprint
typeset -a package_keys
typeset package

for package in "${ALL_PACKAGES[@]}"
do
  srcinfo_file="$SCRIPT_DIR/$package/.SRCINFO"
  package_keys=(
    "${(@f)$(
      awk -F ' = ' '
        {
          key=$1
          sub(/^[[:space:]]+/, "", key)
          if (key == "validpgpkeys") {
            print $2
          }
        }
      ' "$srcinfo_file"
    )}"
  )

  for key_fingerprint in "${package_keys[@]}"
  do
    [[ -n $key_fingerprint ]] && source_keys[$key_fingerprint]=1
  done
done

for key_fingerprint in ${(ok)source_keys}
do
  if sudo --set-home -u "$BUILD_USER" -- gpg --batch \
    --list-keys "$key_fingerprint" >/dev/null 2>&1
  then
    continue
  fi

  print -r -- "Importing source signing key $key_fingerprint"

  if ! sudo --set-home -u "$BUILD_USER" -- gpg --batch \
    --keyserver "$SOURCE_KEYSERVER" --recv-keys "$key_fingerprint"
  then
    print -u2 -r -- \
      "ERROR Could not import source signing key: $key_fingerprint"
    exit 1
  fi
done

sync_package_version()
{
  typeset package=$1

  LC_ALL=C pacman -Si "core/$package" |
    awk -F ':' '
      $1 ~ /^Version[[:space:]]*$/ {
        sub(/^[[:space:]]+/, "", $2)
        sub(/[[:space:]]+$/, "", $2)
        print $2
        exit
      }
    '
}

typeset installed_version
typeset sync_version

for package in "${OFFICIAL_PATCHED_PACKAGES[@]}"
do
  installed_version=$(pacman -Q "$package" 2>/dev/null | awk '{print $2}')
  sync_version=$(sync_package_version "$package")

  if [[ -z $installed_version || -z $sync_version ]]
  then
    print -u2 -r -- "ERROR Could not resolve official version for $package"
    exit 1
  fi

  if [[ $installed_version != $sync_version ]]
  then
    print -u2 -r -- \
      "ERROR $package is not pristine: installed=$installed_version official=$sync_version"
    exit 1
  fi
done

for package in "${AUR_PACKAGES[@]}" selinux-refpolicy-arch
do
  if pacman -Q "$package" >/dev/null 2>&1
  then
    print -u2 -r -- "ERROR Custom package is already installed: $package"
    exit 1
  fi
done

print -r -- "Build environment is ready"
print -r -- "Build user: $BUILD_USER"
print -r -- "Build root: $BUILD_ROOT"
