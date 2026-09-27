#!/usr/bin/env bash
# Post-conditions of profiles/optional/zorin-pro-parity.yaml (optional module "zorin-pro-parity").
# shellcheck source=tests/assertions/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

assert_zorin_pro_parity() {
    ASSERT_MODULE=zorin-pro-parity
    mapfile -t apps < <(profile_query optional/zorin-pro-parity.yaml flatpaks)
    assert_flatpaks "zorin-pro-parity" "${apps[@]}"
}

assert_main assert_zorin_pro_parity
