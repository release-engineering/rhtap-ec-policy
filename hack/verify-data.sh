#!/usr/bin/env bash

set -o errexit
set -o pipefail
set -o nounset

cd "$(git rev-parse --show-toplevel)"

# Verify known_rpm_repositories.yml has been updated with entries from extra_rpm_repositories.yml.
# Only check freshness against the remote source when RPM repository files are part of the change.
# The scheduled update_rpm_repositories workflow keeps the file in sync automatically.
rpm_files_changed=false
if git diff --name-only "${GITHUB_BASE_REF:-main}...HEAD" -- \
    data/known_rpm_repositories.yml \
    hack/extra_rpm_repositories.yml \
    hack/suppressed_rpm_repositories.yml \
    hack/render-known-rpm-repositories.sh \
    hack/update-known-rpm-repositories.sh 2>/dev/null | grep -q .; then
  rpm_files_changed=true
fi

if [[ "${rpm_files_changed}" == "true" ]]; then
  outdated="$(./hack/render-known-rpm-repositories.sh | diff data/known_rpm_repositories.yml - || true)"
  if [[ -n "${outdated}" && "${outdated}" != "[]" ]]; then
      echo "Out of date items found:"
      echo "${outdated}"
      echo "❌ Run hack/update-known-rpm-repositories.sh"
      exit 1
  fi
  echo '✅ data/known_rpm_repositories.yml has expected extras'
else
  echo '⏭️  Skipping RPM repositories freshness check (no relevant files changed)'
fi

# The konflux tag is what is used in Konflux prod. It is updated weekly. For reference:
# https://github.com/redhat-appstudio/infra-deployments/blob/main/components/enterprise-contract/ecp.yaml
# https://github.com/enterprise-contract/infra-deployments-ci/blob/main/.github/workflows/konflux-policy.yaml
# Check against them both to potentially catch an immediate breakage and a future breakage.
for tag in konflux latest; do

  # The EC policy does not allow for relative paths. For this reason, we use envsubst to replace
  # occurrences of $PWD with the actual working directory. The result is a temporary policy file
  # with absolute paths.
  # NOTE: An alternative to saving the modified policy to a temporary file is to use a heredoc, e.g.
  # `ec validate input --file <(...)` However, when doing so, the file name is something like
  # `/dev/fd/63` which EC does not understand as neither a JSON nor a YAML file. Instead EC tries to
  # fetch such resource from a Kubernetes cluster 😅
  POLICY_YAML="$(mktemp --suffix '.yaml')"
  < policy.yaml env POLICY_TAG=$tag envsubst '$PWD,$POLICY_TAG' > "${POLICY_YAML}"

  echo "🔍 Policy config to valiate:"
  < "${POLICY_YAML}" yq .

  ec validate policy --policy "${POLICY_YAML}"
  echo "✅ Policy config validated ($tag tag)"

  # The command requires --file to be used at least once. This sets the input to be verified by the
  # policy rules. However, here we are verifying the data sources which does not require an input.
  # So we use a dummy input file instead.
  ec validate input --policy "${POLICY_YAML}" --output yaml --file hack/empty.json | yq .
  echo "✅ Data validated ($tag tag)"

  rm -f "${POLICY_YAML}"
done
