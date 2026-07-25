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

typeset -a database_files=(
  "$REPOSITORY_DIR/selinux.db"
  "$REPOSITORY_DIR/selinux.files"
)
typeset database_file
typeset confirmation_status
typeset -i signed_count=0
typeset -i existing_count=0

for database_file in "${database_files[@]}"
do
  if [[ ! -f $database_file ]]
  then
    print -u2 -r -- "ERROR Repository database is missing: $database_file"
    exit 1
  fi

  print -r -- ""
  print -r -- "==> ${database_file:t}"

  if [[ -e "$database_file.sig" ]] &&
    verify_detached_signature "$database_file" "$database_file.sig"
  then
    print -r -- "Valid signature already exists"
    (( existing_count += 1 ))
    continue
  fi

  if (( PROMPT_ENABLED ))
  then
    confirm_action "Sign ${database_file:t}?"
    confirmation_status=$?

    if (( confirmation_status != 0 ))
    then
      print -u2 -r -- "Signing aborted before ${database_file:t}"
      exit "$confirmation_status"
    fi
  fi

  sign_file "$database_file" || exit 1
  (( signed_count += 1 ))
done

print -r -- ""
print -r -- "Signed databases: $signed_count"
print -r -- "Existing valid signatures: $existing_count"
