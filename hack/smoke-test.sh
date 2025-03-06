#!/bin/bash -e

POLICY=./hack/policy/smoketest.yaml
#IMAGE=quay.io/konflux-ci/oras:latest
IMAGE=quay.io/konflux-ci/ec-golden-image:latest

# For the logs
cosign tree $IMAGE

# Extract git details from the provenance
gitexpression='.payload | @base64d | fromjson | .predicate.buildConfig.tasks[0].invocation.environment.annotations | ."pipelinesascode.tekton.dev/repo-url" + " " + ."pipelinesascode.tekton.dev/sha"'
GITDETAILS=$(cosign download attestation $IMAGE | jq -r "${gitexpression}")
GITREPO=$(echo $GITDETAILS | awk '{ print $1 }')
GITREF=$(echo $GITDETAILS | awk '{ print $2 }')

# Find the original location of the image at the time of attestation
quayexpression='.payload | @base64d | fromjson | .subject[0].name'
BUILDTIME_IMAGE=$(cosign download attestation $IMAGE | jq -r "${quayexpression}"):$GITREF

# Build a JSON blob to verify
IMAGEJSON=$(echo "{}" | jq '.components += [ {"containerImage": "'"$BUILDTIME_IMAGE"'", "source": {"git": {"revision": "'"${GITREF}"'", "url": "'"${GITREPO}"'"}}} ]')

# And verify it.
if ec --debug validate --quiet image --images "${IMAGEJSON}" --ignore-rekor --policy "${POLICY}"; then
	echo "✅ All good. ${IMAGE} validated successfully"
	exit 0
else
	echo "❌ Something failed."
	exit 1
fi
