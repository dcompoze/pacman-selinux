#!/usr/bin/env zsh

typeset -gr WORKFLOW_DIR=${0:A:h}
source "$WORKFLOW_DIR/package-groups.zsh"

typeset -gr DEFAULT_ARTIFACTS_DIR="$WORKFLOW_DIR/artifacts"
typeset -gr DEFAULT_REPOSITORY_DIR="$DEFAULT_ARTIFACTS_DIR/repository"
typeset -gr DEFAULT_BUILD_ROOT=/var/tmp/pacman-selinux-build
typeset -gr DEFAULT_SIGNING_KEY=BC4B3FA1ECBF048D49EB91FB7C378F4243F0A153
typeset -gr GITHUB_REPOSITORY=dcompoze/pacman-selinux
typeset -gr EXPECTED_SUPERPROJECT_ORIGIN=https://github.com/dcompoze/pacman-selinux
typeset -gr EXPECTED_PACKAGER='dcompoze <contact@dcsoftware.xyz>'
typeset -gr EXPECTED_PACKAGE_GROUP=selinux

typeset -gr ARTIFACTS_DIR=${PACMAN_ARTIFACTS_DIR:-$DEFAULT_ARTIFACTS_DIR}
typeset -gr REPOSITORY_DIR=${PACMAN_REPOSITORY_DIR:-$ARTIFACTS_DIR/repository}
typeset -gr BUILD_ROOT=${PACMAN_BUILD_ROOT:-$DEFAULT_BUILD_ROOT}
typeset -gr SIGNING_KEY=${PACMAN_SIGNING_KEY:-$DEFAULT_SIGNING_KEY}

typeset -gra PACKAGE_SUFFIXES=(
  pkg.tar
  pkg.tar.zst
  pkg.tar.xz
  pkg.tar.gz
  pkg.tar.bz2
  pkg.tar.lrz
  pkg.tar.lz4
  pkg.tar.lzo
  pkg.tar.Z
)

require_disposable_build_container()
{
  typeset container_runtime=

  if command -v systemd-detect-virt >/dev/null 2>&1
  then
    container_runtime=$(systemd-detect-virt --container 2>/dev/null) || true
  fi

  if [[ $container_runtime == docker || $container_runtime == podman ||
    -e /.dockerenv || -e /run/.containerenv ]]
  then
    return 0
  fi

  print -u2 -r -- \
    "ERROR Package setup and builds must run inside Docker or Podman"
  return 1
}

confirm_action()
{
  typeset prompt=$1
  typeset answer
  typeset read_status

  while true
  do
    read -r "answer?$prompt [Y/n] "
    read_status=$?

    if (( read_status != 0 ))
    then
      print -u2 -r -- ""
      print -u2 -r -- "ERROR Input closed while waiting for confirmation"
      return 2
    fi

    answer=${answer:l}

    if [[ -z $answer || $answer == y || $answer == yes ]]
    then
      return 0
    fi

    if [[ $answer == n || $answer == no ]]
    then
      return 1
    fi

    print -u2 -r -- "Please answer y or n"
  done
}

parse_prompt_option()
{
  typeset -gi PROMPT_ENABLED=1

  if (( $# == 1 )) && [[ $1 == --no-prompt ]]
  then
    PROMPT_ENABLED=0
  elif (( $# != 0 ))
  then
    print -u2 -r -- "ERROR The only supported option is --no-prompt"
    return 2
  fi
}

package_metadata_field()
{
  typeset package_file=$1
  typeset field=$2

  bsdtar -xOf "$package_file" .PKGINFO |
    awk -F ' = ' -v field="$field" '$1 == field {print $2; exit}'
}

package_metadata_has_value()
{
  typeset package_file=$1
  typeset field=$2
  typeset expected_value=$3

  bsdtar -xOf "$package_file" .PKGINFO |
    awk -F ' = ' -v field="$field" -v expected="$expected_value" '
      $1 == field && $2 == expected {
        found=1
      }
      END {
        exit !found
      }
    '
}

collect_package_files()
{
  typeset suffix

  PACKAGE_FILES=()

  for suffix in "${PACKAGE_SUFFIXES[@]}"
  do
    PACKAGE_FILES+=("$REPOSITORY_DIR"/*.$suffix(N.))
  done
}

is_published_package()
{
  typeset candidate=$1
  typeset expected

  for expected in "${PUBLISHED_PACKAGE_NAMES[@]}"
  do
    if [[ $candidate == $expected ]]
    then
      return 0
    fi
  done

  return 1
}

validate_package_artifacts()
{
  typeset package_file
  typeset package_name
  typeset package_arch
  typeset package_packager
  typeset expected
  typeset -gA ARTIFACT_BY_PACKAGE
  typeset -ga PACKAGE_FILES

  ARTIFACT_BY_PACKAGE=()
  collect_package_files

  if (( ${#PACKAGE_FILES} == 0 ))
  then
    print -u2 -r -- "ERROR No package artifacts found in $REPOSITORY_DIR"
    return 1
  fi

  for package_file in "${PACKAGE_FILES[@]}"
  do
    package_name=$(package_metadata_field "$package_file" pkgname)
    package_arch=$(package_metadata_field "$package_file" arch)
    package_packager=$(package_metadata_field "$package_file" packager)

    if [[ -z $package_name || -z $package_arch || -z $package_packager ]]
    then
      print -u2 -r -- "ERROR Could not read package metadata: $package_file"
      return 1
    fi

    if ! is_published_package "$package_name"
    then
      print -u2 -r -- "ERROR Unexpected package artifact: ${package_file:t}"
      return 1
    fi

    if [[ $package_arch != x86_64 && $package_arch != any ]]
    then
      print -u2 -r -- \
        "ERROR Unsupported package architecture for $package_name: $package_arch"
      return 1
    fi

    if ! package_metadata_has_value \
      "$package_file" group "$EXPECTED_PACKAGE_GROUP"
    then
      print -u2 -r -- \
        "ERROR $package_name does not belong to $EXPECTED_PACKAGE_GROUP"
      return 1
    fi

    if [[ $package_packager != $EXPECTED_PACKAGER ]]
    then
      print -u2 -r -- \
        "ERROR Unexpected packager for $package_name: $package_packager"
      return 1
    fi

    if [[ -n ${ARTIFACT_BY_PACKAGE[$package_name]-} ]]
    then
      print -u2 -r -- "ERROR Duplicate package artifact: $package_name"
      return 1
    fi

    ARTIFACT_BY_PACKAGE[$package_name]=$package_file
  done

  for expected in "${PUBLISHED_PACKAGE_NAMES[@]}"
  do
    if [[ -z ${ARTIFACT_BY_PACKAGE[$expected]-} ]]
    then
      print -u2 -r -- "ERROR Missing package artifact: $expected"
      return 1
    fi
  done

  if (( ${#PACKAGE_FILES} != ${#PUBLISHED_PACKAGE_NAMES} ))
  then
    print -u2 -r -- "ERROR Package artifact count does not match the allowlist"
    return 1
  fi
}

validate_build_manifest()
{
  typeset manifest_file="$REPOSITORY_DIR/build-manifest.json"
  typeset package_name
  typeset package_file
  typeset package_hash
  typeset expected_names_json

  if [[ ! -f $manifest_file ]]
  then
    print -u2 -r -- "ERROR Build manifest is missing: $manifest_file"
    return 1
  fi

  if ! jq -e \
    --argjson expected_count "${#PUBLISHED_PACKAGE_NAMES[@]}" \
    --arg expected_packager "$EXPECTED_PACKAGER" \
    '
      .schema_version == 1 and
      .complete == true and
      .architecture == "x86_64" and
      .packager == $expected_packager and
      (.superproject_commit | type == "string" and length == 40) and
      (.packages | type == "array" and length == $expected_count)
    ' "$manifest_file" >/dev/null
  then
    print -u2 -r -- "ERROR Build manifest is incomplete or invalid"
    return 1
  fi

  expected_names_json=$(
    jq -cn --args '$ARGS.positional' "${PUBLISHED_PACKAGE_NAMES[@]}"
  ) || return 1

  if ! jq -e --argjson expected "$expected_names_json" \
    '.published_packages == $expected' "$manifest_file" >/dev/null
  then
    print -u2 -r -- "ERROR Build manifest package allowlist differs"
    return 1
  fi

  validate_package_artifacts || return 1

  for package_name in "${PUBLISHED_PACKAGE_NAMES[@]}"
  do
    package_file=${ARTIFACT_BY_PACKAGE[$package_name]}
    package_hash=$(sha256sum "$package_file" | awk '{print $1}')

    if ! jq -e \
      --arg name "$package_name" \
      --arg file "${package_file:t}" \
      --arg sha256 "$package_hash" \
      '
        [
          .packages[] |
          select(
            .name == $name and
            .file == $file and
            .sha256 == $sha256
          )
        ] |
        length == 1
      ' "$manifest_file" >/dev/null
    then
      print -u2 -r -- \
        "ERROR Build manifest does not match package artifact: $package_name"
      return 1
    fi
  done
}

verify_detached_signature()
{
  typeset signed_file=$1
  typeset signature_file=$2
  typeset status_output
  typeset line
  typeset -a fields

  if ! status_output=$(
    gpg --batch --status-fd 1 \
      --verify "$signature_file" "$signed_file" 2>/dev/null
  )
  then
    return 1
  fi

  for line in ${(f)status_output}
  do
    if [[ $line == "[GNUPG:] VALIDSIG "* ]]
    then
      fields=(${=line})

      if [[ ${fields[3]-} == $SIGNING_KEY || ${fields[-1]-} == $SIGNING_KEY ]]
      then
        return 0
      fi
    fi
  done

  return 1
}

require_secret_signing_key()
{
  typeset tty_device

  if ! command -v gpg >/dev/null 2>&1
  then
    print -u2 -r -- "ERROR gpg is not installed"
    return 1
  fi

  if [[ -t 0 ]] && command -v tty >/dev/null 2>&1
  then
    tty_device=$(tty 2>/dev/null)

    if [[ -n $tty_device && $tty_device != "not a tty" ]]
    then
      export GPG_TTY=$tty_device

      if command -v gpg-connect-agent >/dev/null 2>&1
      then
        gpg-connect-agent updatestartuptty /bye >/dev/null 2>&1 || true
      fi
    fi
  fi

  if ! gpg --batch --list-secret-keys "$SIGNING_KEY" >/dev/null 2>&1
  then
    print -u2 -r -- "ERROR Secret signing key is not available: $SIGNING_KEY"
    return 1
  fi
}

sign_file()
{
  typeset signed_file=$1
  typeset signature_file="$signed_file.sig"

  if [[ -e $signature_file ]]
  then
    if verify_detached_signature "$signed_file" "$signature_file"
    then
      print -r -- "Valid signature already exists"
      return 0
    fi

    print -u2 -r -- \
      "ERROR [${signed_file:t}] Existing signature is invalid or uses another key"
    return 1
  fi

  if ! gpg --local-user "$SIGNING_KEY" --detach-sign \
    --output "$signature_file" "$signed_file"
  then
    rm -f -- "$signature_file"
    print -u2 -r -- "ERROR [${signed_file:t}] Could not create signature"
    return 1
  fi

  if ! verify_detached_signature "$signed_file" "$signature_file"
  then
    rm -f -- "$signature_file"
    print -u2 -r -- \
      "ERROR [${signed_file:t}] Created signature failed verification"
    return 1
  fi

  print -r -- "Signed ${signed_file:t}"
}
