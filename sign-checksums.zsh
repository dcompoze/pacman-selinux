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

require_secret_signing_key || exit 1
validate_build_manifest || exit 1

typeset -gr CHECKSUM_FILE="$REPOSITORY_DIR/SHA256SUMS"

if [[ ! -f $CHECKSUM_FILE ]]
then
  print -u2 -r -- "ERROR SHA256SUMS is missing"
  exit 1
fi

if ! (
  cd "$REPOSITORY_DIR" || exit 1
  sha256sum -c --quiet SHA256SUMS
)
then
  print -u2 -r -- "ERROR SHA256SUMS verification failed"
  exit 1
fi

if [[ -e "$CHECKSUM_FILE.sig" ]] &&
  verify_detached_signature "$CHECKSUM_FILE" "$CHECKSUM_FILE.sig"
then
  print -r -- "Valid SHA256SUMS signature already exists"
  exit 0
fi

if (( PROMPT_ENABLED ))
then
  confirm_action "Sign SHA256SUMS?" || exit $?
fi

sign_file "$CHECKSUM_FILE"
