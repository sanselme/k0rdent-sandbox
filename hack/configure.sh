#!/bin/bash
set -exo pipefail

: "${LOCALE:="C.UTF-8"}"
: "${TIMEZONE:="America/Toronto"}"

# disable swap
swapoff -a && sed -ri '/\sswap\s/s/^#?/#/' /etc/fstab || true

# set locale
localectl set-locale LANG="${LOCALE}"

# set timezone
timedatectl set-ntp true
timedatectl set-timezone "${TIMEZONE}"
