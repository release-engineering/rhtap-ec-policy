#!/usr/bin/env bash

set -o errexit
set -o pipefail
set -o nounset

cd "$(git rev-parse --show-toplevel)"

MAIN_FILE="data/trusted_task_rules.yaml"
MAIN_DENY_KEY="konflux-defaults"
DEPRECATED_FILE="data/trusted_task_rules_deprecated.yaml"
DEPRECATED_DENY_KEY="konflux-defaults-deprecated"
GRACE_PERIOD_SHORT=30
GRACE_PERIOD_LONG=60

date_plus_days() {
  date -u -d "+${1} days" +%Y-%m-%dT00:00:00Z
}

EFFECTIVE_SHORT=$(date_plus_days "$GRACE_PERIOD_SHORT")
EFFECTIVE_LONG=$(date_plus_days "$GRACE_PERIOD_LONG")

MAIN_SOURCES=(
  quay.io/konflux-ci/tekton-catalog/data-acceptable-bundles:latest
)

DEPRECATED_SOURCES=(
  quay.io/konflux-ci/integration-service-catalog/data-acceptable-bundles:latest
  quay.io/konflux-ci/konflux-vanguard/data-acceptable-bundles:latest
)

extract_oci_versions() {
  jq -r '
    .trusted_tasks | keys[] |
    capture("^oci://(?<repo>quay\\.io/konflux-ci/.+):(?<version>[0-9]+\\.[0-9]+(\\.[0-9]+)?)$") |
    select(. != null) |
    "\(.repo) \(.version)"
  '
}

fetch_sources() {
  local sources=("$@")
  local all_data=""
  for source in "${sources[@]}"; do
    >&2 echo "Fetching ${source}..."
    local data
    data=$(ec inspect policy-data --source "${source}" 2>/dev/null)
    local extracted
    extracted=$(echo "$data" | extract_oci_versions)
    if [[ -n "$extracted" ]]; then
      all_data+="${extracted}"$'\n'
    fi
  done
  echo "$all_data"
}

generate_deny_rules() {
  local all_data="$1"

  local repos
  repos=$(echo "$all_data" | awk '{print $1}' | sort -u)

  declare -A repo_catalog
  while IFS=' ' read -r repo version; do
    [[ -z "$repo" ]] && continue
    if [[ -z "${repo_catalog[$repo]+x}" ]]; then
      local catalog
      catalog=$(echo "$repo" | awk -F'/' '{print $2"/"$3}')
      repo_catalog[$repo]="$catalog"
    fi
  done <<< "$all_data"

  declare -A catalog_repos
  for repo in $repos; do
    [[ -z "$repo" ]] && continue
    local catalog="${repo_catalog[$repo]}"
    catalog_repos[$catalog]+="$repo"$'\n'
  done

  local first=true
  for catalog in $(echo "${!catalog_repos[@]}" | tr ' ' '\n' | sort); do
    local has_rules=false

    while IFS= read -r repo; do
      [[ -z "$repo" ]] && continue

      local minor_versions
      minor_versions=$(echo "$all_data" | awk -v r="$repo" '$1 == r {print $2}' | awk -F'.' '{print $2}' | sort -n -u)
      local count
      count=$(echo "$minor_versions" | wc -l)
      local max_minor
      max_minor=$(echo "$minor_versions" | tail -1)

      if ! $has_rules; then
        $first || echo ""
        first=false
        echo "        #-------------------------------------"
        echo "        # ${catalog}"
        echo "        #-------------------------------------"
        has_rules=true
      fi

      task_name="${repo##*/}"
      task_name="${task_name#task-}"
      echo ""
      echo "        # ${task_name}"
      if [[ "$count" -ge 3 ]]; then
        local floor1=$((max_minor - 1))
        echo "        - pattern: oci://${repo}"
        echo "          versions: ['<0.${floor1}']"
        echo "          effective_on: \"${EFFECTIVE_SHORT}\""
        echo "        - pattern: oci://${repo}"
        echo "          versions: ['<0.${max_minor}']"
        echo "          effective_on: \"${EFFECTIVE_LONG}\""
      elif [[ "$count" -eq 2 ]]; then
        echo "        - pattern: oci://${repo}"
        echo "          versions: ['<0.${max_minor}']"
        echo "          effective_on: \"${EFFECTIVE_LONG}\""
      else
        echo "        - pattern: oci://${repo}"
        echo "          versions: ['<0.1']"
      fi
    done <<< "${catalog_repos[$catalog]}"

  done
}

# Preserve everything up to and including the deny key line
preserve_header() {
  local file="$1"
  local deny_key="$2"
  local deny_marker="      ${deny_key}:"
  local found_deny=false
  while IFS= read -r line; do
    echo "$line"
    if [[ "$line" == "$deny_marker" ]] && $found_deny; then
      return
    fi
    if [[ "$line" == "    deny:" ]]; then
      found_deny=true
    fi
  done < "$file"
}

update_file() {
  local file="$1"
  local deny_key="$2"
  local data="$3"

  local tmpfile
  tmpfile=$(mktemp)

  preserve_header "$file" "$deny_key" > "$tmpfile"
  generate_deny_rules "$data" >> "$tmpfile"
  mv "$tmpfile" "$file"
  >&2 echo "Updated ${file}"
}

main_data=$(fetch_sources "${MAIN_SOURCES[@]}")
update_file "$MAIN_FILE" "$MAIN_DENY_KEY" "$main_data"

deprecated_data=$(fetch_sources "${DEPRECATED_SOURCES[@]}")
update_file "$DEPRECATED_FILE" "$DEPRECATED_DENY_KEY" "$deprecated_data"
