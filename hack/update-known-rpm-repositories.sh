#!/usr/bin/env bash

set -o errexit
set -o pipefail
set -o nounset

cd "$(git rev-parse --show-toplevel)"

hack/render-known-rpm-repositories.sh > data/known_rpm_repositories.yml
