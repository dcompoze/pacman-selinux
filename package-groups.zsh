#!/usr/bin/env zsh

# Shared package groups and branch mappings for repository maintenance scripts.

typeset -gra PATCHED_PACKAGES=(
  coreutils
  dbus-broker
  dbus
  openssh
  pam
  pambase
  shadow
  sudo
  systemd
  util-linux
  selinux-refpolicy-arch
)

typeset -gra OFFICIAL_PATCHED_PACKAGES=(
  coreutils
  dbus-broker
  dbus
  openssh
  pam
  pambase
  shadow
  sudo
  systemd
  util-linux
)

typeset -gra AUR_PACKAGES=(
  checkpolicy
  libselinux
  libsemanage
  libsepol
  policycoreutils
  secilc
  selinux-alpm-hook
  selinux-python
  semodule-utils
  setools
)

typeset -gra ALL_PACKAGES=(
  "${PATCHED_PACKAGES[@]}"
  "${AUR_PACKAGES[@]}"
)

typeset -gra BUILD_ORDER=(
  libsepol
  libselinux
  libsemanage
  checkpolicy
  secilc
  semodule-utils
  setools
  pambase
  coreutils
  pam
  shadow
  dbus
  util-linux
  systemd
  dbus-broker
  openssh
  sudo
  policycoreutils
  selinux-python
  selinux-refpolicy-arch
  selinux-alpm-hook
)

typeset -gra NOCHECK_PACKAGE_BASES=(
  coreutils
  util-linux
  systemd
)

typeset -gra PUBLISHED_PACKAGE_NAMES=(
  coreutils
  util-linux
  util-linux-libs
  systemd
  systemd-libs
  systemd-resolvconf
  systemd-sysvcompat
  pam
  pambase
  shadow
  sudo
  dbus
  dbus-broker
  openssh
  checkpolicy
  libselinux
  libsemanage
  libsepol
  policycoreutils
  secilc
  selinux-alpm-hook
  selinux-python
  selinux-refpolicy-arch
  semodule-utils
  setools
)

typeset -grA PUBLISHED_OUTPUTS=(
  coreutils coreutils
  util-linux "util-linux util-linux-libs"
  systemd "systemd systemd-libs systemd-resolvconf systemd-sysvcompat"
  pam pam
  pambase pambase
  shadow shadow
  sudo sudo
  dbus dbus
  dbus-broker dbus-broker
  openssh openssh
  checkpolicy checkpolicy
  libselinux libselinux
  libsemanage libsemanage
  libsepol libsepol
  policycoreutils policycoreutils
  secilc secilc
  selinux-alpm-hook selinux-alpm-hook
  selinux-python selinux-python
  selinux-refpolicy-arch selinux-refpolicy-arch
  semodule-utils semodule-utils
  setools setools
)

typeset -grA INTERMEDIATE_INSTALLS=(
  libsepol libsepol
  libselinux libselinux
  libsemanage libsemanage
  checkpolicy checkpolicy
  secilc ""
  semodule-utils semodule-utils
  setools setools
  pambase pambase
  coreutils coreutils
  pam pam
  shadow shadow
  dbus dbus
  util-linux "util-linux util-linux-libs"
  systemd "systemd systemd-libs"
  dbus-broker ""
  openssh ""
  sudo ""
  policycoreutils policycoreutils
  selinux-python ""
  selinux-refpolicy-arch ""
  selinux-alpm-hook ""
)

typeset -grA UPSTREAM_BRANCHES=(
  coreutils main
  dbus-broker main
  dbus main
  openssh main
  pam main
  pambase main
  shadow main
  sudo main
  systemd main
  util-linux main
  selinux-refpolicy-arch master
)

# Select the packaging tag currently released in Arch core, including pkgrel.
# Update the tag and its full commit together before rebasing SELinux changes.
# main continues to track origin/main, which may contain testing packages.
typeset -grA OFFICIAL_BASE_TAGS=(
  coreutils 9.12-2
  dbus-broker 37-3
  dbus 1.16.2-2
  openssh 10.6p1-2
  pam 1.7.3-1
  pambase 20260616-1
  shadow 4.20.0.arch1-1
  sudo 1.9.17.p2-6
  systemd 262.1-1
  util-linux 2.42.4-1
)

typeset -grA OFFICIAL_BASE_COMMITS=(
  coreutils 67c9b5e28295ac576db0bfc38aac77defc8c21b2
  dbus-broker 007302346bc4e1bc878b208047f27d86d620f39b
  dbus b2153405ecdc7a07b53dae7aa2e3e25b8e5ac7f9
  openssh a6ca1d5c3352c394e56751badefbe865e5a4d431
  pam 8d366d7b5a846cc26dcbb99c5123ff5413ba81b6
  pambase 18ff110e2b4181d8b84bccdf86525cf2a50ad20d
  shadow b9fd1505550d16a29861b4a0f6ac2de9a6d51a5a
  sudo 169bfd01a1ad3fdc24c83335a9039a1369ca160b
  systemd 83e49870f69d70cce91321b165a69ef788c869be
  util-linux 1959b6ecef6b57acd92ca97b783553174b747f6a
)

typeset -grA PATCHED_BRANCHES=(
  coreutils selinux
  dbus-broker selinux
  dbus selinux
  openssh selinux
  pam selinux
  pambase selinux
  shadow selinux
  sudo selinux
  systemd selinux
  util-linux selinux
  selinux-refpolicy-arch custom
)

typeset -grA ORIGIN_URLS=(
  coreutils https://gitlab.archlinux.org/archlinux/packaging/packages/coreutils
  dbus-broker https://gitlab.archlinux.org/archlinux/packaging/packages/dbus-broker
  dbus https://gitlab.archlinux.org/archlinux/packaging/packages/dbus
  openssh https://gitlab.archlinux.org/archlinux/packaging/packages/openssh
  pam https://gitlab.archlinux.org/archlinux/packaging/packages/pam
  pambase https://gitlab.archlinux.org/archlinux/packaging/packages/pambase
  shadow https://gitlab.archlinux.org/archlinux/packaging/packages/shadow
  sudo https://gitlab.archlinux.org/archlinux/packaging/packages/sudo
  systemd https://gitlab.archlinux.org/archlinux/packaging/packages/systemd
  util-linux https://gitlab.archlinux.org/archlinux/packaging/packages/util-linux
  selinux-refpolicy-arch https://aur.archlinux.org/selinux-refpolicy-arch
  checkpolicy https://aur.archlinux.org/checkpolicy.git
  libselinux https://aur.archlinux.org/libselinux.git
  libsemanage https://aur.archlinux.org/libsemanage.git
  libsepol https://aur.archlinux.org/libsepol.git
  policycoreutils https://aur.archlinux.org/policycoreutils.git
  secilc https://aur.archlinux.org/secilc
  selinux-alpm-hook https://aur.archlinux.org/selinux-alpm-hook
  selinux-python https://aur.archlinux.org/selinux-python.git
  semodule-utils https://aur.archlinux.org/semodule-utils
  setools https://aur.archlinux.org/setools.git
)

typeset -grA SUBMODULE_URLS=(
  coreutils https://github.com/dcompoze/coreutils
  dbus-broker https://github.com/dcompoze/dbus-broker
  dbus https://github.com/dcompoze/dbus
  openssh https://github.com/dcompoze/openssh
  pam https://github.com/dcompoze/pam
  pambase https://github.com/dcompoze/pambase
  shadow https://github.com/dcompoze/shadow
  sudo https://github.com/dcompoze/sudo
  systemd https://github.com/dcompoze/systemd
  util-linux https://github.com/dcompoze/util-linux
  selinux-refpolicy-arch https://github.com/dcompoze/selinux-refpolicy-arch
  checkpolicy https://aur.archlinux.org/checkpolicy.git
  libselinux https://aur.archlinux.org/libselinux.git
  libsemanage https://aur.archlinux.org/libsemanage.git
  libsepol https://aur.archlinux.org/libsepol.git
  policycoreutils https://aur.archlinux.org/policycoreutils.git
  secilc https://aur.archlinux.org/secilc
  selinux-alpm-hook https://aur.archlinux.org/selinux-alpm-hook
  selinux-python https://aur.archlinux.org/selinux-python.git
  semodule-utils https://aur.archlinux.org/semodule-utils
  setools https://aur.archlinux.org/setools.git
)

typeset -grA SUBMODULE_BRANCHES=(
  coreutils selinux
  dbus-broker selinux
  dbus selinux
  openssh selinux
  pam selinux
  pambase selinux
  shadow selinux
  sudo selinux
  systemd selinux
  util-linux selinux
  selinux-refpolicy-arch custom
  checkpolicy master
  libselinux master
  libsemanage master
  libsepol master
  policycoreutils master
  secilc master
  selinux-alpm-hook master
  selinux-python master
  semodule-utils master
  setools master
)

typeset -grA TRACKING_REMOTES=(
  coreutils github
  dbus-broker github
  dbus github
  openssh github
  pam github
  pambase github
  shadow github
  sudo github
  systemd github
  util-linux github
  selinux-refpolicy-arch github
  checkpolicy origin
  libselinux origin
  libsemanage origin
  libsepol origin
  policycoreutils origin
  secilc origin
  selinux-alpm-hook origin
  selinux-python origin
  semodule-utils origin
  setools origin
)
