#!/usr/bin/env zsh

emulate -L zsh
setopt NO_UNSET PIPE_FAIL

typeset -gr SCRIPT_DIR=${0:A:h}
source "$SCRIPT_DIR/release-common.zsh"

parse_prompt_option "$@" || exit $?

if [[ ! -d $REPOSITORY_DIR ]]
then
  print -u2 -r -- "ERROR Repository directory does not exist: $REPOSITORY_DIR"
  exit 1
fi

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

typeset package_name
typeset package_file
typeset confirmation_status
typeset -i signed_count=0
typeset -i existing_count=0

for package_name in "${PUBLISHED_PACKAGE_NAMES[@]}"
do
  package_file=${ARTIFACT_BY_PACKAGE[$package_name]}

  print -r -- ""
  print -r -- "==> ${package_file:t}"

  if [[ -e "$package_file.sig" ]] &&
    verify_detached_signature "$package_file" "$package_file.sig"
  then
    print -r -- "Valid signature already exists"
    (( existing_count += 1 ))
    continue
  fi

  if (( PROMPT_ENABLED ))
  then
    confirm_action "Sign ${package_file:t}?"
    confirmation_status=$?

    if (( confirmation_status != 0 ))
    then
      print -u2 -r -- "Signing aborted before ${package_file:t}"
      exit "$confirmation_status"
    fi
  fi

  sign_file "$package_file" || exit 1
  (( signed_count += 1 ))
done

print -r -- ""
print -r -- "Signed packages: $signed_count"
print -r -- "Existing valid signatures: $existing_count"
