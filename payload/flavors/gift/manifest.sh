#!/usr/bin/env bash
# Builders in a Box — gift flavor manifest.
#
# Activates the personalised welcome flow used when handing a pre-built
# box to a specific recipient. The maintainer materials (welcome card,
# explainer PDF, delivery plan) live in flavors/gift/maintainer/ and are
# `export-ignore`-d so they never reach the recipient's device.
#
# To produce a gift box for a recipient called e.g. "Maria":
#   BIB_NAME="Maria" sudo install.sh --flavor=gift
# Note that the ASCII banner below currently hardcodes a specific four-
# letter name in block characters. Re-rendering the banner for arbitrary
# names is future maintainer work (figlet pipeline) — for now, edit the
# block-character rows directly if you want a different name to appear.

BIB_FLAVOR_NAME="gift"
BIB_FLAVOR_COPY_DIR="${BIB_INSTALL_ROOT}/payload/flavors/gift/copy"
export BIB_FLAVOR_NAME BIB_FLAVOR_COPY_DIR

# Override the neutral wizard_banner from lib/prompt.sh with the
# personalised ASCII art preserved from v0.1 of the gift flavor.
wizard_banner() {
    local c="${BIB_BRIGHT_CYAN:-}" r="${BIB_RESET:-}"
    local m="${BIB_BOLD:-}${BIB_BRIGHT_MAGENTA:-}"
    local b="${BIB_BOLD:-}${BIB_BRIGHT_CYAN:-}"
    local W=76

    _line() {
        local color="$1" payload="$2" width="$3"
        local total_pad=$(( W - width ))
        local left=$(( total_pad / 2 ))
        local right=$(( total_pad - left ))
        printf '  %s|%*s%s%s%s%*s%s|%s\n' \
            "$c" "$left" "" "$color" "$payload" "$r" "$right" "" "$c" "$r"
    }
    _blank() { printf '  %s|%*s|%s\n' "$c" "$W" "" "$r"; }
    _rule()  { printf '  %s+%s+%s\n' "$c" "$(printf '=%.0s' $(seq 1 $W))" "$r"; }

    printf '\n'
    _rule
    _blank
    _line "$m" '██████   █████   █████   █████ '  31
    _line "$m" '██   ██ ██   ██ ██      ██   ██'  31
    _line "$m" '██████  ███████ ██      ██   ██'  31
    _line "$m" '██      ██   ██ ██      ██   ██'  31
    _line "$m" '██      ██   ██  █████   █████ '  31
    _blank
    _line "$b" ' ___ _   _ ___ _    ___  ___ ___  ___   ___ _  _    _    ___  _____  __' 71
    _line "$b" '| _ ) | | |_ _| |  |   \| __| _ \/ __| |_ _| \| |  /_\  | _ )/ _ \ \/ /'  71
    _line "$b" '| _ \ |_| || || |__| |) | _||   /\__ \  | || .` | / _ \ | _ \ (_) >  < ' 71
    _line "$b" '|___/\___/|___|____|___/|___|_|_\|___/ |___|_|\_|/_/ \_\|___/\___/_/\_\' 71
    _blank
    _rule
    printf '\n'
}
