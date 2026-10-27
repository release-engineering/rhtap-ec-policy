#!/bin/bash
set -euo pipefail

POLICY=./hack/policy/smoketest.yaml
#IMAGE=quay.io/konflux-ci/oras:latest
IMAGE=quay.io/konflux-ci/ec-golden-image:latest

# For the logs
cosign tree "$IMAGE"

# Read the build-time image and Git source from the SLSA v1 provenance.
if ! COMPONENT=$(cosign download attestation "$IMAGE" | jq -ec '
  .payload | @base64d | fromjson |
  .predicate.buildDefinition.externalParameters.runSpec.params as $params |
  {
    containerImage: ([$params[] | select(.name == "output-image") | .value][0]),
    source: {git: {
      url: ([$params[] | select(.name == "git-url") | .value][0]),
      revision: ([$params[] | select(.name == "revision") | .value][0])
    }}
  } |
  select(.containerImage != null and .containerImage != "" and
         .source.git.url != null and .source.git.url != "" and
         .source.git.revision != null and .source.git.revision != "")
'); then
  echo "❌ Could not extract image and Git source from the attestation." >&2
  exit 1
fi

IMAGEJSON=$(jq -nc --argjson component "$COMPONENT" '{components: [$component]}')

# And verify it.
if ec validate --quiet image --images "${IMAGEJSON}" --ignore-rekor --policy "${POLICY}"; then
	echo "✅ All good. ${IMAGE} validated successfully"
	exit 0
else
	echo "❌ Something failed."
	exit 1
fi
