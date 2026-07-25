#!/usr/bin/env zsh

emulate -L zsh
setopt NO_UNSET PIPE_FAIL

typeset -gr SCRIPT_DIR=${0:A:h}
source "$SCRIPT_DIR/release-common.zsh"

parse_prompt_option "$@" || exit $?

for command in bsdtar gpg jq repo-add sha256sum
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

for package_name in "${PUBLISHED_PACKAGE_NAMES[@]}"
do
  package_file=${ARTIFACT_BY_PACKAGE[$package_name]}

  if [[ ! -f "$package_file.sig" ]]
  then
    print -u2 -r -- "ERROR Missing package signature: ${package_file:t}.sig"
    exit 1
  fi

  if ! verify_detached_signature "$package_file" "$package_file.sig"
  then
    print -u2 -r -- "ERROR Invalid package signature: ${package_file:t}.sig"
    exit 1
  fi
done

typeset -gra FINAL_DATABASE_FILES=(
  "$REPOSITORY_DIR/selinux.db"
  "$REPOSITORY_DIR/selinux.db.sig"
  "$REPOSITORY_DIR/selinux.files"
  "$REPOSITORY_DIR/selinux.files.sig"
)
typeset database_file

for database_file in "${FINAL_DATABASE_FILES[@]}"
do
  if [[ -e $database_file ]]
  then
    print -u2 -r -- "ERROR Repository database output already exists: $database_file"
    exit 1
  fi
done

if (( PROMPT_ENABLED ))
then
  confirm_action "Create the selinux package repository databases?" || exit $?
fi

typeset -gr DATABASE_ARCHIVE="$REPOSITORY_DIR/selinux.db.tar.zst"
typeset -gr FILES_ARCHIVE="$REPOSITORY_DIR/selinux.files.tar.zst"
typeset temporary_directory
typeset -a ordered_package_files

for package_name in "${PUBLISHED_PACKAGE_NAMES[@]}"
do
  ordered_package_files+=("${ARTIFACT_BY_PACKAGE[$package_name]}")
done

temporary_directory=$(mktemp -d "$REPOSITORY_DIR/.database.XXXXXX") ||
  exit 1

cleanup_working_database()
{
  rm -f -- \
    "$REPOSITORY_DIR/selinux.db" \
    "$REPOSITORY_DIR/selinux.files" \
    "$DATABASE_ARCHIVE" \
    "$FILES_ARCHIVE" \
    "$DATABASE_ARCHIVE.old" \
    "$FILES_ARCHIVE.old" \
    "$DATABASE_ARCHIVE.lck"
}

if ! repo-add --include-sigs "$DATABASE_ARCHIVE" \
  "${ordered_package_files[@]}"
then
  cleanup_working_database
  rm -rf -- "$temporary_directory"
  print -u2 -r -- "ERROR repo-add failed"
  exit 1
fi

if [[ ! -e "$REPOSITORY_DIR/selinux.db" ||
  ! -e "$REPOSITORY_DIR/selinux.files" ]]
then
  cleanup_working_database
  rm -rf -- "$temporary_directory"
  print -u2 -r -- "ERROR repo-add did not create both databases"
  exit 1
fi

if ! cp -L -- "$REPOSITORY_DIR/selinux.db" \
  "$temporary_directory/selinux.db" ||
  ! cp -L -- "$REPOSITORY_DIR/selinux.files" \
  "$temporary_directory/selinux.files"
then
  cleanup_working_database
  rm -rf -- "$temporary_directory"
  print -u2 -r -- "ERROR Could not materialize repository databases"
  exit 1
fi

cleanup_working_database

if ! mv -- "$temporary_directory/selinux.db" \
  "$REPOSITORY_DIR/selinux.db" ||
  ! mv -- "$temporary_directory/selinux.files" \
  "$REPOSITORY_DIR/selinux.files"
then
  rm -f -- \
    "$REPOSITORY_DIR/selinux.db" \
    "$REPOSITORY_DIR/selinux.files"
  rm -rf -- "$temporary_directory"
  print -u2 -r -- "ERROR Could not install repository databases"
  exit 1
fi

rmdir -- "$temporary_directory"

print -r -- "Created selinux.db"
print -r -- "Created selinux.files"
