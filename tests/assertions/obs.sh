#!/usr/bin/env bash
# Post-conditions of profiles/optional/obs.yaml (optional module "obs").
# shellcheck source=tests/assertions/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

assert_obs() {
    ASSERT_MODULE=obs
    mapfile -t apps < <(profile_query optional/obs.yaml flatpaks)
    assert_flatpaks "obs" "${apps[@]}"
}

assert_main assert_obs
