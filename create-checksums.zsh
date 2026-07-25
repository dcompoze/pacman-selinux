#!/usr/bin/env zsh

emulate -L zsh
setopt NO_UNSET PIPE_FAIL

typeset -gr SCRIPT_DIR=${0:A:h}
source "$SCRIPT_DIR/release-common.zsh"

parse_prompt_option "$@" || exit $?

for command in bsdtar gpg jq sha256sum
do
  if ! command -v "$command" >/dev/null 2>&1
  then
    print -u2 -r -- "ERROR Required command is missing: $command"
    exit 1
  fi
done

validate_build_manifest || exit 1

typeset package_name
typeset package_file
typeset signed_file
typeset -a checksum_files
typeset -a metadata_files=(
  "$REPOSITORY_DIR/build-manifest.json"
  "$REPOSITORY_DIR/selinux.db"
  "$REPOSITORY_DIR/selinux.db.sig"
  "$REPOSITORY_DIR/selinux.files"
  "$REPOSITORY_DIR/selinux.files.sig"
)

for package_name in "${PUBLISHED_PACKAGE_NAMES[@]}"
do
  package_file=${ARTIFACT_BY_PACKAGE[$package_name]}
  checksum_files+=("$package_file" "$package_file.sig")

  if [[ ! -f "$package_file.sig" ]] ||
    ! verify_detached_signature "$package_file" "$package_file.sig"
  then
    print -u2 -r -- "ERROR Invalid package signature: ${package_file:t}.sig"
    exit 1
  fi
done

checksum_files+=("${metadata_files[@]}")

for signed_file in "${checksum_files[@]}"
do
  if [[ ! -f $signed_file ]]
  then
    print -u2 -r -- "ERROR Release asset is missing: $signed_file"
    exit 1
  fi
done

for signed_file in \
  "$REPOSITORY_DIR/selinux.db" \
  "$REPOSITORY_DIR/selinux.files"
do
  if ! verify_detached_signature "$signed_file" "$signed_file.sig"
  then
    print -u2 -r -- "ERROR Invalid repository signature: ${signed_file:t}.sig"
    exit 1
  fi
done

if [[ -e "$REPOSITORY_DIR/SHA256SUMS.sig" ]]
then
  print -u2 -r -- \
    "ERROR Remove the existing SHA256SUMS.sig before regenerating checksums"
  exit 1
fi

if (( PROMPT_ENABLED ))
then
  confirm_action "Create SHA256SUMS for all release assets?" || exit $?
fi

typeset temporary_checksums

temporary_checksums=$(mktemp "$REPOSITORY_DIR/.SHA256SUMS.XXXXXX") ||
  exit 1

if ! (
  cd "$REPOSITORY_DIR" || exit 1
  LC_ALL=C sha256sum -- ${(on)${checksum_files:t}}
) > "$temporary_checksums"
then
  rm -f -- "$temporary_checksums"
  print -u2 -r -- "ERROR Could not create SHA256SUMS"
  exit 1
fi

chmod 0644 "$temporary_checksums"
mv -f -- "$temporary_checksums" "$REPOSITORY_DIR/SHA256SUMS"

print -r -- "Created SHA256SUMS"
