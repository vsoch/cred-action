#!/bin/bash
set -eu
set -o pipefail

# This script uses the scripts/build-static-site.sh provided in the container
# and customizes the entrypoint based on what the user has provided.
# We derive variables from the environment instead of command line

# Tell the user files found immediately
echo "Found files in workspace:"
ls

build_cmd=( /bin/bash /build_static_site.sh  --target "${INPUT_TARGET}" )

# Project file and if are both required for generation!
# The action requires, but we have the double check here for a fallback
if [ -z "${INPUT_PROJECT_FILE}" ]; then
    echo "Project file (project-file) is required"
    exit 1
fi
build_cmd+=( --project-file "${INPUT_PROJECT_FILE}" )

# Weights are not required, added if defined
if [ ! -z "${INPUT_WEIGHTS}" ]; then
    build_cmd+=( --weights "${INPUT_WEIGHTS}" )
fi

# Show the user where we are
echo "Present working directory is:"
echo "${PWD}"
ls

# Clean up any previous runs (deployed in docs folder)
# This command needs to be run relative to sourcecred respository
# that is located at the WORKDIR /code
rm -rf "${INPUT_TARGET}"
printf '%s\n' "${build_cmd[*]}"
"${build_cmd[@]}"

echo "Finished initial run, present working directory is ${PWD}"
ls

# This interacts with node sourcecred.js
# Load it twice so we can access the scores -- it's a hack, pending real instance system
# Note from @vsoch: these variable names aren't consistent - the project here referes to the project file.
load_cmd=( node /code/bin/sourcecred.js load \
    --project "${INPUT_PROJECT_FILE}" )
if [ ! -z "${INPUT_WEIGHTS}" ]; then
    load_cmd+=( --weights "${INPUT_WEIGHTS}" )
fi
printf '%s\n' "${load_cmd[*]}"
"${load_cmd[@]}"
node /code/bin/sourcecred.js scores "${INPUT_PROJECT}" | python3 -m json.tool > "${INPUT_SCORES_JSON}"

# Automated means that we push to a branch, otherwise we open a pull request
if [ "${INPUT_AUTOMATED}" == "true" ]; then
    echo "Automated PR requested"
    UPDATE_BRANCH="${INPUT_BRANCH_AGAINST}"
else
    UPDATE_BRANCH="update/sourcecred-cred-$(date '+%Y-%m-%d')"
fi

if [ "${INPUT_TEST_RUN}" == "true" ]; then
    printf "Test run detected, exiting with 0.\n"
    exit 0
fi

echo "GitHub Actor: ${GITHUB_ACTOR}"
git remote set-url origin "https://x-access-token:${GITHUB_TOKEN}@github.com/${GITHUB_REPOSITORY}.git"
git branch
git config --global user.name "github-actions"
git config --global user.email "github-actions@users.noreply.github.com"

export UPDATE_BRANCH
echo "Branch to update is ${UPDATE_BRANCH}"
git checkout -b "${UPDATE_BRANCH}"
git branch

if [ "${INPUT_AUTOMATED}" == "true" ]; then
    git pull origin "${UPDATE_BRANCH}" || echo "Branch not yet on remote"
    git add "${INPUT_TARGET}/*"
    git add "${INPUT_SCORES_JSON}"
    git commit -m "Automated deployment to update cred in ${INPUT_TARGET} $(date '+%Y-%m-%d')"
    git push origin "${UPDATE_BRANCH}"
else
    git add "${INPUT_TARGET}/*"
    git add "${INPUT_SCORES_JSON}"
    git commit -m "Automated deployment to update ${INPUT_TARGET} static files $(date '+%Y-%m-%d')"
    git push origin "${UPDATE_BRANCH}"
    /bin/bash -e /pull_request.sh
fi
