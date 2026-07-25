#!/usr/bin/env zsh

emulate -L zsh
setopt NO_UNSET PIPE_FAIL

typeset -gr SCRIPT_DIR=${0:A:h}
source "$SCRIPT_DIR/release-common.zsh"

parse_build_options()
{
  typeset -gi PROMPT_ENABLED=1
  typeset -g RESUME_FROM=

  while (( $# > 0 ))
  do
    case $1 in
      --no-prompt)
        PROMPT_ENABLED=0
        ;;
      --from)
        shift

        if (( $# == 0 )) || [[ -z $1 ]]
        then
          print -u2 -r -- "ERROR --from requires a package base"
          return 2
        fi

        if [[ -n $RESUME_FROM ]]
        then
          print -u2 -r -- "ERROR --from may only be specified once"
          return 2
        fi

        RESUME_FROM=$1
        ;;
      --from=*)
        if [[ -n $RESUME_FROM ]]
        then
          print -u2 -r -- "ERROR --from may only be specified once"
          return 2
        fi

        RESUME_FROM=${1#--from=}

        if [[ -z $RESUME_FROM ]]
        then
          print -u2 -r -- "ERROR --from requires a package base"
          return 2
        fi
        ;;
      *)
        print -u2 -r -- "ERROR Unsupported option: $1"
        print -u2 -r -- \
          "Usage: ${0:t} [--no-prompt] [--from <package-base>]"
        return 2
        ;;
    esac

    shift
  done
}

parse_build_options "$@" || exit $?

typeset -gr BUILD_USER=pacman-build
typeset -gr PACKAGER_NAME=$EXPECTED_PACKAGER
typeset BUILD_GROUP
typeset BUILD_PATH
typeset -ga COMPLETED_PACKAGE_BASES
typeset -ga PACKAGES_TO_BUILD

select_build_range()
{
  typeset package
  typeset -i found=0

  COMPLETED_PACKAGE_BASES=()
  PACKAGES_TO_BUILD=()

  if [[ -z $RESUME_FROM ]]
  then
    PACKAGES_TO_BUILD=("${BUILD_ORDER[@]}")
    return 0
  fi

  for package in "${BUILD_ORDER[@]}"
  do
    if [[ $package == $RESUME_FROM ]]
    then
      found=1
    fi

    if (( found ))
    then
      PACKAGES_TO_BUILD+=("$package")
    else
      COMPLETED_PACKAGE_BASES+=("$package")
    fi
  done

  if (( ! found ))
  then
    print -u2 -r -- "ERROR Unknown build package base: $RESUME_FROM"
    return 2
  fi
}

select_build_range || exit $?

package_skips_checks()
{
  typeset candidate=$1
  typeset package

  for package in "${NOCHECK_PACKAGE_BASES[@]}"
  do
    if [[ $candidate == $package ]]
    then
      return 0
    fi
  done

  return 1
}

fail()
{
  print -u2 -r -- "ERROR $1"
  exit 1
}

directory_is_empty()
{
  typeset directory=$1
  typeset -a entries

  [[ ! -d $directory ]] && return 0
  entries=("$directory"/*(DN))
  (( ${#entries} == 0 ))
}

validate_generated_path()
{
  typeset path=${1:A}

  if [[ $path == / || $path == /tmp || $path == /var/tmp ||
    $path == $SCRIPT_DIR ]]
  then
    return 1
  fi

  [[ $path == /tmp/* || $path == /var/tmp/* ||
    $path == "$SCRIPT_DIR"/artifacts(|/*) ]]
}

srcinfo_value()
{
  typeset srcinfo_file=$1
  typeset field=$2

  awk -F ' = ' -v field="$field" '
    {
      key=$1
      sub(/^[[:space:]]+/, "", key)
      if (key == field) {
        print $2
        exit
      }
    }
  ' "$srcinfo_file"
}

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

validate_superproject()
{
  typeset dirty_state
  typeset package
  typeset repository
  typeset recorded_commit
  typeset checked_out_commit
  typeset checked_out_branch
  typeset intended_branch
  typeset tracking_remote

  if ! git -C "$SCRIPT_DIR" rev-parse --show-toplevel >/dev/null 2>&1
  then
    fail "Top-level directory is not a Git repository"
  fi

  dirty_state=$(
    git -C "$SCRIPT_DIR" status --porcelain \
      --untracked-files=all --ignore-submodules=none
  )

  if [[ -n $dirty_state ]]
  then
    print -u2 -r -- "$dirty_state"
    fail "Superproject or submodule state is not clean"
  fi

  for package in "${ALL_PACKAGES[@]}"
  do
    repository="$SCRIPT_DIR/$package"
    intended_branch=${SUBMODULE_BRANCHES[$package]}
    tracking_remote=${TRACKING_REMOTES[$package]}

    if ! git -C "$repository" rev-parse --is-inside-work-tree \
      >/dev/null 2>&1
    then
      fail "Submodule is not initialized: $package"
    fi

    recorded_commit=$(git -C "$SCRIPT_DIR" rev-parse ":$package")
    checked_out_commit=$(git -C "$repository" rev-parse HEAD)

    if [[ $recorded_commit != $checked_out_commit ]]
    then
      fail "$package HEAD does not match the recorded gitlink"
    fi

    checked_out_branch=$(
      git -C "$repository" symbolic-ref --quiet --short HEAD
    )

    if [[ $checked_out_branch != $intended_branch ]]
    then
      fail "$package must be checked out on $intended_branch"
    fi

    if ! git -C "$repository" fetch --prune "$tracking_remote"
    then
      fail "Could not fetch $tracking_remote for $package"
    fi

    if ! git -C "$repository" show-ref --verify --quiet \
      "refs/remotes/$tracking_remote/$intended_branch"
    then
      fail "Missing $tracking_remote/$intended_branch for $package"
    fi

    if ! git -C "$repository" merge-base --is-ancestor HEAD \
      "refs/remotes/$tracking_remote/$intended_branch"
    then
      fail "$package HEAD is not available on $tracking_remote/$intended_branch"
    fi
  done
}

validate_official_versions()
{
  typeset package
  typeset srcinfo_file
  typeset recipe_epoch
  typeset recipe_pkgver
  typeset recipe_pkgrel
  typeset recipe_base_version
  typeset recipe_full_version
  typeset official_version
  typeset official_base_version

  for package in "${OFFICIAL_PATCHED_PACKAGES[@]}"
  do
    srcinfo_file="$SCRIPT_DIR/$package/.SRCINFO"
    recipe_epoch=$(srcinfo_value "$srcinfo_file" epoch)
    recipe_pkgver=$(srcinfo_value "$srcinfo_file" pkgver)
    recipe_pkgrel=$(srcinfo_value "$srcinfo_file" pkgrel)

    if [[ -z $recipe_pkgver || -z $recipe_pkgrel ]]
    then
      fail "Could not read version metadata for $package"
    fi

    recipe_base_version="${recipe_epoch:+$recipe_epoch:}$recipe_pkgver"
    recipe_full_version="$recipe_base_version-$recipe_pkgrel"
    official_version=$(sync_package_version "$package")
    official_base_version=${official_version%-*}

    if [[ -z $official_version ]]
    then
      fail "Could not resolve official version for $package"
    fi

    if [[ $recipe_base_version != $official_base_version ]]
    then
      fail "$package upstream version differs: recipe=$recipe_base_version official=$official_base_version"
    fi

    if (( $(vercmp "$recipe_full_version" "$official_version") <= 0 ))
    then
      fail "$package must exceed the official version: recipe=$recipe_full_version official=$official_version"
    fi
  done
}

validate_pristine_installed_packages()
{
  typeset package
  typeset installed_version
  typeset official_version

  for package in "${OFFICIAL_PATCHED_PACKAGES[@]}"
  do
    installed_version=$(pacman -Q "$package" 2>/dev/null | awk '{print $2}')
    official_version=$(sync_package_version "$package")

    if [[ -z $installed_version || -z $official_version ]]
    then
      fail "Could not resolve bootstrap version for $package"
    fi

    if [[ $installed_version != $official_version ]]
    then
      fail \
        "$package is not pristine: installed=$installed_version official=$official_version"
    fi
  done

  for package in "${AUR_PACKAGES[@]}" selinux-refpolicy-arch
  do
    if pacman -Q "$package" >/dev/null 2>&1
    then
      fail "Custom package is already installed: $package"
    fi
  done
}

validate_source_keys()
{
  typeset package
  typeset srcinfo_file
  typeset key_fingerprint
  typeset -a package_keys
  typeset -A source_keys

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

  for key_fingerprint in ${(k)source_keys}
  do
    if ! sudo --set-home -u "$BUILD_USER" -- gpg --batch \
      --list-keys "$key_fingerprint" >/dev/null 2>&1
    then
      fail "Source signing key is missing: $key_fingerprint"
    fi
  done
}

prepare_makepkg_config()
{
  typeset config_file=$1
  typeset package_output=$2
  typeset package_logs=$3
  typeset package_root=${config_file:h}

  cp -- /etc/makepkg.conf "$config_file" || return 1

  {
    print -r -- ""
    print -r -- "PACKAGER='$PACKAGER_NAME'"
    print -r -- "PKGDEST='$package_output'"
    print -r -- "LOGDEST='$package_logs'"
    print -r -- "SRCDEST='$package_root/sources'"
    print -r -- "SRCPKGDEST='$package_root/source-packages'"
    print -r -- "BUILDDIR='$package_root/build'"
    print -r -- "PKGEXT='.pkg.tar.zst'"
    print -r -- 'OPTIONS=("${OPTIONS[@]/#debug/!debug}")'
  } >> "$config_file"
}

copy_package_logs()
{
  typeset package=$1
  typeset package_logs=$2
  typeset destination="$ARTIFACTS_DIR/logs/$package"
  typeset -a log_files

  log_files=("$package_logs"/*(N.))
  (( ${#log_files} == 0 )) && return 0

  install -d -m 0755 "$destination" || return 1
  cp -p -- "${log_files[@]}" "$destination/"
}

typeset -A BUILT_ARTIFACTS
typeset -gr BUILD_STATE_FILE="$BUILD_ROOT/build-state.json"

recipe_full_version()
{
  typeset package=$1
  typeset srcinfo_file="$SCRIPT_DIR/$package/.SRCINFO"
  typeset recipe_epoch
  typeset recipe_pkgver
  typeset recipe_pkgrel

  recipe_epoch=$(srcinfo_value "$srcinfo_file" epoch)
  recipe_pkgver=$(srcinfo_value "$srcinfo_file" pkgver)
  recipe_pkgrel=$(srcinfo_value "$srcinfo_file" pkgrel)

  if [[ -z $recipe_pkgver || -z $recipe_pkgrel ]]
  then
    return 1
  fi

  print -r -- \
    "${recipe_epoch:+$recipe_epoch:}$recipe_pkgver-$recipe_pkgrel"
}

validate_resume_artifacts()
{
  typeset package
  typeset output_name
  typeset output_names
  typeset package_file
  typeset package_name
  typeset package_arch
  typeset package_version
  typeset expected_version
  typeset entry
  typeset -a repository_entries
  typeset -A expected_base_by_name
  typeset -A package_file_set

  BUILT_ARTIFACTS=()

  for package in "${COMPLETED_PACKAGE_BASES[@]}"
  do
    output_names=${PUBLISHED_OUTPUTS[$package]}

    for output_name in ${=output_names}
    do
      expected_base_by_name[$output_name]=$package
    done
  done

  collect_package_files
  repository_entries=("$REPOSITORY_DIR"/*(DN))

  for package_file in "${PACKAGE_FILES[@]}"
  do
    package_file_set[$package_file]=1
  done

  for entry in "${repository_entries[@]}"
  do
    if [[ -z ${package_file_set[$entry]-} ]]
    then
      print -u2 -r -- \
        "ERROR Resume repository contains an unexpected file: ${entry:t}"
      return 1
    fi
  done

  if (( ${#PACKAGE_FILES} != ${#expected_base_by_name} ))
  then
    print -u2 -r -- \
      "ERROR Resume artifact count does not match completed package bases"
    return 1
  fi

  for package_file in "${PACKAGE_FILES[@]}"
  do
    package_name=$(package_metadata_field "$package_file" pkgname)
    package_arch=$(package_metadata_field "$package_file" arch)
    package_version=$(package_metadata_field "$package_file" pkgver)

    if [[ -z $package_name || -z $package_arch || -z $package_version ]]
    then
      print -u2 -r -- \
        "ERROR Could not read resume artifact metadata: ${package_file:t}"
      return 1
    fi

    if [[ -z ${expected_base_by_name[$package_name]-} ]]
    then
      print -u2 -r -- \
        "ERROR Unexpected resume artifact: ${package_file:t}"
      return 1
    fi

    if [[ $package_arch != x86_64 && $package_arch != any ]]
    then
      print -u2 -r -- \
        "ERROR Unsupported package architecture for $package_name: $package_arch"
      return 1
    fi

    if [[ -n ${BUILT_ARTIFACTS[$package_name]-} ]]
    then
      print -u2 -r -- "ERROR Duplicate resume artifact: $package_name"
      return 1
    fi

    package=${expected_base_by_name[$package_name]}
    expected_version=$(recipe_full_version "$package") || {
      print -u2 -r -- \
        "ERROR Could not resolve expected version for $package"
      return 1
    }

    if [[ $package_version != $expected_version ]]
    then
      print -u2 -r -- \
        "ERROR Resume artifact version differs for $package_name: artifact=$package_version expected=$expected_version"
      return 1
    fi

    BUILT_ARTIFACTS[$package_name]=$package_file
  done

  for output_name in ${(k)expected_base_by_name}
  do
    if [[ -z ${BUILT_ARTIFACTS[$output_name]-} ]]
    then
      print -u2 -r -- "ERROR Missing resume artifact: $output_name"
      return 1
    fi
  done
}

validate_resume_installed_packages()
{
  typeset package
  typeset install_name
  typeset install_names
  typeset installed_version
  typeset expected_version
  typeset official_version
  typeset -A installed_from_artifact

  for package in "${COMPLETED_PACKAGE_BASES[@]}"
  do
    install_names=${INTERMEDIATE_INSTALLS[$package]}

    for install_name in ${=install_names}
    do
      installed_from_artifact[$install_name]=1
      installed_version=$(
        pacman -Q "$install_name" 2>/dev/null | awk '{print $2}'
      )
      expected_version=$(
        package_metadata_field "${BUILT_ARTIFACTS[$install_name]}" pkgver
      )

      if [[ -z $installed_version || $installed_version != $expected_version ]]
      then
        fail \
          "Resume dependency differs for $install_name: installed=${installed_version:-missing} expected=$expected_version"
      fi
    done
  done

  for package in "${OFFICIAL_PATCHED_PACKAGES[@]}"
  do
    if [[ -n ${installed_from_artifact[$package]-} ]]
    then
      continue
    fi

    installed_version=$(pacman -Q "$package" 2>/dev/null | awk '{print $2}')
    official_version=$(sync_package_version "$package")

    if [[ -z $installed_version || $installed_version != $official_version ]]
    then
      fail \
        "$package is not pristine for resume: installed=${installed_version:-missing} official=$official_version"
    fi
  done
}

validate_resume_build_state()
{
  typeset package
  typeset expected_bases_json
  typeset recorded_commit
  typeset current_commit

  if [[ ! -f $BUILD_STATE_FILE ]]
  then
    print -r -- \
      "Adopting validated partial artifacts from the earlier build"
    return 0
  fi

  expected_bases_json=$(
    jq -cn --args '$ARGS.positional' "${COMPLETED_PACKAGE_BASES[@]}"
  ) || return 1

  if ! jq -e \
    --argjson expected "$expected_bases_json" \
    '
      .schema_version == 1 and
      .completed_package_bases == $expected and
      (.submodules | type == "array")
    ' "$BUILD_STATE_FILE" >/dev/null
  then
    print -u2 -r -- \
      "ERROR Build state does not match --from $RESUME_FROM"
    return 1
  fi

  for package in "${COMPLETED_PACKAGE_BASES[@]}"
  do
    recorded_commit=$(
      jq -er --arg name "$package" \
        '.submodules[] | select(.name == $name) | .commit' \
        "$BUILD_STATE_FILE"
    ) || {
      print -u2 -r -- \
        "ERROR Build state is missing the commit for $package"
      return 1
    }
    current_commit=$(git -C "$SCRIPT_DIR/$package" rev-parse HEAD)

    if [[ $recorded_commit != $current_commit ]]
    then
      print -u2 -r -- \
        "ERROR Completed package source changed since build: $package"
      return 1
    fi
  done
}

write_build_state()
{
  typeset package
  typeset state_temp
  typeset completed_bases_json
  typeset submodule_records="$BUILD_ROOT/build-state-submodules.jsonl"
  typeset submodules_json

  : > "$submodule_records" || return 1

  for package in "${COMPLETED_PACKAGE_BASES[@]}"
  do
    jq -cn \
      --arg name "$package" \
      --arg commit "$(git -C "$SCRIPT_DIR/$package" rev-parse HEAD)" \
      '{name: $name, commit: $commit}' >> "$submodule_records" ||
      return 1
  done

  completed_bases_json=$(
    jq -cn --args '$ARGS.positional' "${COMPLETED_PACKAGE_BASES[@]}"
  ) || return 1
  submodules_json=$(jq -sc . "$submodule_records") || return 1
  state_temp=$(mktemp "$BUILD_ROOT/.build-state.XXXXXX") || return 1

  if ! jq -n \
    --argjson completed_package_bases "$completed_bases_json" \
    --argjson submodules "$submodules_json" \
    '{
      schema_version: 1,
      completed_package_bases: $completed_package_bases,
      submodules: $submodules
    }' > "$state_temp"
  then
    rm -f -- "$state_temp"
    return 1
  fi

  mv -f -- "$state_temp" "$BUILD_STATE_FILE"
}

retain_selected_outputs()
{
  typeset package=$1
  typeset package_output=$2
  typeset output_names=${PUBLISHED_OUTPUTS[$package]}
  typeset output_file
  typeset output_name
  typeset expected_name
  typeset destination
  typeset -a expected_names
  typeset -a output_files
  typeset -A expected_set
  typeset -A retained_set

  expected_names=(${=output_names})

  for expected_name in "${expected_names[@]}"
  do
    expected_set[$expected_name]=1
  done

  output_files=("$package_output"/*.pkg.tar.*(N.))

  if (( ${#output_files} == 0 ))
  then
    print -u2 -r -- "ERROR [$package] makepkg produced no package artifacts"
    return 1
  fi

  for output_file in "${output_files[@]}"
  do
    output_name=$(package_metadata_field "$output_file" pkgname)

    if [[ -z $output_name ]]
    then
      print -u2 -r -- \
        "ERROR [$package] Could not read ${output_file:t}"
      return 1
    fi

    if [[ -z ${expected_set[$output_name]-} ]]
    then
      print -r -- "Discarding unpublished split output: $output_name"
      continue
    fi

    if [[ -n ${retained_set[$output_name]-} ||
      -n ${BUILT_ARTIFACTS[$output_name]-} ]]
    then
      print -u2 -r -- "ERROR [$package] Duplicate output: $output_name"
      return 1
    fi

    destination="$REPOSITORY_DIR/${output_file:t}"
    cp -p -- "$output_file" "$destination" || return 1
    retained_set[$output_name]=1
    BUILT_ARTIFACTS[$output_name]=$destination
  done

  for expected_name in "${expected_names[@]}"
  do
    if [[ -z ${retained_set[$expected_name]-} ]]
    then
      print -u2 -r -- \
        "ERROR [$package] Missing expected output: $expected_name"
      return 1
    fi
  done
}

install_intermediate_outputs()
{
  typeset package=$1
  typeset install_names=${INTERMEDIATE_INSTALLS[$package]}
  typeset install_name
  typeset -a install_files

  [[ -z $install_names ]] && return 0

  for install_name in ${=install_names}
  do
    if [[ -z ${BUILT_ARTIFACTS[$install_name]-} ]]
    then
      print -u2 -r -- \
        "ERROR [$package] Missing intermediate package: $install_name"
      return 1
    fi

    install_files+=("${BUILT_ARTIFACTS[$install_name]}")
  done

  pacman -U --needed --noconfirm -- "${install_files[@]}"
}

build_one_package()
{
  typeset package=$1
  typeset repository="$SCRIPT_DIR/$package"
  typeset package_root="$BUILD_ROOT/$package"
  typeset source_directory="$package_root/source"
  typeset package_output="$package_root/output"
  typeset package_logs="$package_root/logs"
  typeset archive_file="$package_root/source.tar"
  typeset config_file="$package_root/makepkg.conf"
  typeset generated_srcinfo="$package_root/.SRCINFO.generated"
  typeset -a makepkg_options

  if [[ -e $package_root ]]
  then
    if [[ ${package_root:A} != ${BUILD_ROOT:A}/$package ]]
    then
      print -u2 -r -- \
        "ERROR [$package] Unsafe package build directory: $package_root"
      return 1
    fi

    if ! rm -rf -- "$package_root"
    then
      print -u2 -r -- \
        "ERROR [$package] Could not reset package build directory"
      return 1
    fi
  fi

  if ! install -d -m 0755 \
    "$source_directory" \
    "$package_output" \
    "$package_logs" \
    "$package_root/sources" \
    "$package_root/source-packages" \
    "$package_root/build"
  then
    print -u2 -r -- "ERROR [$package] Could not prepare build directories"
    return 1
  fi

  if ! git -C "$repository" archive --format=tar \
    --output="$archive_file" HEAD
  then
    print -u2 -r -- "ERROR [$package] Could not export committed source"
    return 1
  fi

  if ! bsdtar -xf "$archive_file" -C "$source_directory"
  then
    print -u2 -r -- "ERROR [$package] Could not extract committed source"
    return 1
  fi

  rm -f -- "$archive_file"

  if ! prepare_makepkg_config "$config_file" "$package_output" "$package_logs"
  then
    print -u2 -r -- "ERROR [$package] Could not prepare makepkg.conf"
    return 1
  fi

  if ! chown -R "$BUILD_USER:$BUILD_GROUP" "$package_root"
  then
    print -u2 -r -- "ERROR [$package] Could not assign build ownership"
    return 1
  fi

  if ! sudo --set-home -u "$BUILD_USER" -- \
    env PATH="$BUILD_PATH" makepkg \
    --config "$config_file" --dir "$source_directory" \
    --printsrcinfo > "$generated_srcinfo"
  then
    print -u2 -r -- "ERROR [$package] Could not generate .SRCINFO"
    return 1
  fi

  if ! cmp -s -- "$generated_srcinfo" "$source_directory/.SRCINFO"
  then
    print -u2 -r -- "ERROR [$package] Committed .SRCINFO is stale"
    diff -u -- "$source_directory/.SRCINFO" "$generated_srcinfo" || true
    return 1
  fi

  makepkg_options=(
    --syncdeps
    --noconfirm
    --cleanbuild
    --log
  )

  if package_skips_checks "$package"
  then
    print -r -- "Skipping check() for $package"
    makepkg_options+=(--nocheck)
  fi

  if ! sudo --set-home -u "$BUILD_USER" -- \
    env PATH="$BUILD_PATH" makepkg \
    --config "$config_file" --dir "$source_directory" \
    "${makepkg_options[@]}"
  then
    copy_package_logs "$package" "$package_logs" || true
    print -u2 -r -- "ERROR [$package] makepkg failed"
    return 1
  fi

  if ! copy_package_logs "$package" "$package_logs"
  then
    print -u2 -r -- "ERROR [$package] Could not preserve build logs"
    return 1
  fi

  if ! retain_selected_outputs "$package" "$package_output"
  then
    return 1
  fi

  if ! install_intermediate_outputs "$package"
  then
    print -u2 -r -- \
      "ERROR [$package] Could not install intermediate package outputs"
    return 1
  fi
}

create_build_manifest()
{
  typeset superproject_commit
  typeset built_at
  typeset package
  typeset package_file
  typeset package_name
  typeset package_version
  typeset package_arch
  typeset package_hash
  typeset submodule_records="$BUILD_ROOT/submodules.jsonl"
  typeset package_records="$BUILD_ROOT/packages.jsonl"
  typeset manifest_file="$BUILD_ROOT/build-manifest.json"
  typeset submodules_json
  typeset packages_json
  typeset build_order_json
  typeset published_names_json

  : > "$submodule_records"
  : > "$package_records"

  superproject_commit=$(git -C "$SCRIPT_DIR" rev-parse HEAD)
  built_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)

  for package in "${ALL_PACKAGES[@]}"
  do
    jq -cn \
      --arg name "$package" \
      --arg commit "$(git -C "$SCRIPT_DIR/$package" rev-parse HEAD)" \
      '{name: $name, commit: $commit}' >> "$submodule_records" ||
      return 1
  done

  validate_package_artifacts || return 1

  for package_name in "${PUBLISHED_PACKAGE_NAMES[@]}"
  do
    package_file=${ARTIFACT_BY_PACKAGE[$package_name]}
    package_version=$(package_metadata_field "$package_file" pkgver)
    package_arch=$(package_metadata_field "$package_file" arch)
    package_hash=$(sha256sum "$package_file" | awk '{print $1}')

    jq -cn \
      --arg name "$package_name" \
      --arg version "$package_version" \
      --arg architecture "$package_arch" \
      --arg file "${package_file:t}" \
      --arg sha256 "$package_hash" \
      '{
        name: $name,
        version: $version,
        architecture: $architecture,
        file: $file,
        sha256: $sha256
      }' >> "$package_records" ||
      return 1
  done

  submodules_json=$(jq -sc . "$submodule_records") || return 1
  packages_json=$(jq -sc . "$package_records") || return 1
  build_order_json=$(jq -cn --args '$ARGS.positional' "${BUILD_ORDER[@]}") ||
    return 1
  published_names_json=$(
    jq -cn --args '$ARGS.positional' "${PUBLISHED_PACKAGE_NAMES[@]}"
  ) || return 1

  jq -n \
    --arg schema_version "1" \
    --arg built_at "$built_at" \
    --arg architecture x86_64 \
    --arg packager "$PACKAGER_NAME" \
    --arg superproject_commit "$superproject_commit" \
    --argjson build_order "$build_order_json" \
    --argjson published_packages "$published_names_json" \
    --argjson submodules "$submodules_json" \
    --argjson packages "$packages_json" \
    '{
      schema_version: ($schema_version | tonumber),
      complete: true,
      built_at: $built_at,
      architecture: $architecture,
      packager: $packager,
      superproject_commit: $superproject_commit,
      build_order: $build_order,
      published_packages: $published_packages,
      submodules: $submodules,
      packages: $packages
    }' > "$manifest_file" ||
    return 1

  cp -p -- "$manifest_file" "$REPOSITORY_DIR/build-manifest.json"
}

if (( EUID != 0 ))
then
  fail "This script must run as root"
fi

if [[ $(uname -m) != x86_64 ]]
then
  fail "The build environment must be x86_64"
fi

if grep -Eq '^[[:space:]]*\[selinux\][[:space:]]*$' /etc/pacman.conf
then
  fail "Do not configure the selinux repository inside the build container"
fi

typeset command

for command in awk bash bsdtar cmp date diff env git gpg jq makepkg \
  mktemp pacman sha256sum sudo vercmp
do
  command -v "$command" >/dev/null 2>&1 ||
    fail "Required command is missing: $command"
done

id "$BUILD_USER" >/dev/null 2>&1 ||
  fail "Build user is missing, run setup-build-environment.zsh first"
BUILD_GROUP=$(id -gn "$BUILD_USER")
BUILD_PATH=$(
  sudo --set-home -u "$BUILD_USER" -- \
    bash -lc 'printf "%s" "$PATH"'
) || fail "Could not resolve the build-user PATH"
[[ -n $BUILD_PATH ]] || fail "Build-user PATH is empty"

if ! sudo --set-home -u "$BUILD_USER" -- sudo -n pacman --version >/dev/null
then
  fail "Build user cannot run pacman, run setup-build-environment.zsh first"
fi

[[ -r /etc/makepkg.conf ]] || fail "/etc/makepkg.conf is missing"
validate_generated_path "$BUILD_ROOT" || fail "Unsafe build root: $BUILD_ROOT"
validate_generated_path "$ARTIFACTS_DIR" ||
  fail "Unsafe artifacts directory: $ARTIFACTS_DIR"

validate_superproject
validate_official_versions
validate_source_keys

if [[ -z $RESUME_FROM ]]
then
  directory_is_empty "$BUILD_ROOT" ||
    fail "Build root is not empty, run cleanup-build-output.zsh first"
  directory_is_empty "$ARTIFACTS_DIR" ||
    fail "Artifacts directory is not empty, run cleanup-build-output.zsh first"
  validate_pristine_installed_packages
else
  [[ -d $BUILD_ROOT ]] ||
    fail "Build root is missing, cannot resume from $RESUME_FROM"
  [[ -d $REPOSITORY_DIR ]] ||
    fail "Artifact repository is missing, cannot resume from $RESUME_FROM"
  [[ ! -e "$REPOSITORY_DIR/build-manifest.json" ]] ||
    fail "Build is already complete and cannot be resumed"

  validate_resume_artifacts ||
    fail "Partial artifacts are invalid for --from $RESUME_FROM"
  validate_resume_build_state ||
    fail "Partial build state is invalid for --from $RESUME_FROM"
  validate_resume_installed_packages
fi

typeset workspace_uid
typeset workspace_gid
typeset package
typeset confirmation_status

workspace_uid=$(stat -c %u "$SCRIPT_DIR")
workspace_gid=$(stat -c %g "$SCRIPT_DIR")

restore_artifact_ownership()
{
  if [[ -e $ARTIFACTS_DIR ]]
  then
    chown -R "$workspace_uid:$workspace_gid" "$ARTIFACTS_DIR"
  fi
}

trap 'restore_artifact_ownership || true' EXIT

install -d -m 0755 -o "$BUILD_USER" -g "$BUILD_GROUP" "$BUILD_ROOT" ||
  fail "Could not prepare build root"
install -d -m 0755 "$REPOSITORY_DIR" "$ARTIFACTS_DIR/logs" ||
  fail "Could not prepare artifact directories"

write_build_state || fail "Could not initialize build state"

for package in "${PACKAGES_TO_BUILD[@]}"
do
  print -r -- ""
  print -r -- "==> $package"

  if (( PROMPT_ENABLED ))
  then
    confirm_action "Build $package?"
    confirmation_status=$?

    if (( confirmation_status != 0 ))
    then
      print -u2 -r -- "Build aborted before $package"
      exit "$confirmation_status"
    fi
  fi

  build_one_package "$package" || exit 1
  COMPLETED_PACKAGE_BASES+=("$package")
  write_build_state || fail "Could not update build state after $package"
done

create_build_manifest || fail "Could not create build manifest"
restore_artifact_ownership || fail "Could not restore artifact ownership"

print -r -- ""
print -r -- "Built package bases: ${#BUILD_ORDER[@]}"
print -r -- "Built in this invocation: ${#PACKAGES_TO_BUILD[@]}"
print -r -- "Published package artifacts: ${#PUBLISHED_PACKAGE_NAMES[@]}"
print -r -- "Build manifest: $REPOSITORY_DIR/build-manifest.json"
