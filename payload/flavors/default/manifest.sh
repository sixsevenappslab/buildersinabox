#!/usr/bin/env bash
# Builders in a Box — default flavor manifest.
#
# Sourced by install.sh after state_init. Exports paths that other scripts
# (wizard/run.sh, lib/prompt.sh) read to locate flavor copy. Can also
# define overrides for wizard_banner() and other UI hooks; the default
# flavor uses the neutral banner defined in lib/prompt.sh, so no override
# here.

BIB_FLAVOR_NAME="default"
BIB_FLAVOR_COPY_DIR="${BIB_INSTALL_ROOT}/payload/flavors/default/copy"
export BIB_FLAVOR_NAME BIB_FLAVOR_COPY_DIR
