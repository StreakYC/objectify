#!/usr/bin/env bash
#
# Publishes this Streak Objectify fork to the mailfoogae Artifact Registry Maven
# repo (gs-backed Maven repo "streak-maven"), which MailFoo consumes instead of a
# released upstream Objectify (see objectify/objectify#527, Valkey cache support).
#
# Usage:
#   ./publish-to-artifact-registry.sh                 # deploy the version in pom.xml
#   ./publish-to-artifact-registry.sh 6.1.4-streak-valkey-3   # set that version, then deploy
#
# Requirements:
#   - Application Default Credentials with roles/artifactregistry.writer on the repo
#     (`gcloud auth application-default login`, or GOOGLE_APPLICATION_CREDENTIALS=<sa-key>).
#   - The pom already carries the artifactregistry-maven-wagon extension and the
#     artifactregistry:// distributionManagement repo (committed on this branch).
#
# Maven: uses `mvn` if on PATH, otherwise downloads a pinned Apache Maven to a temp
# dir (this fork has no mvnw wrapper). Tests need a Datastore emulator, so they are
# skipped for the deploy.
set -euo pipefail

readonly MAVEN_VERSION="3.9.9"
readonly REPO_URL="artifactregistry://us-central1-maven.pkg.dev/mailfoogae/streak-maven"

# Run from the repo root (where pom.xml lives), regardless of invocation directory.
cd "$(cd "$(dirname "$0")" && pwd)"

# --- Resolve a Maven binary ------------------------------------------------------
if command -v mvn >/dev/null 2>&1; then
  MVN="mvn"
else
  readonly MVN_HOME="${TMPDIR:-/tmp}/apache-maven-${MAVEN_VERSION}"
  if [ ! -x "${MVN_HOME}/bin/mvn" ]; then
    echo "==> mvn not on PATH; downloading Apache Maven ${MAVEN_VERSION}"
    curl -fsSL -o "${TMPDIR:-/tmp}/apache-maven-${MAVEN_VERSION}-bin.tar.gz" \
      "https://archive.apache.org/dist/maven/maven-3/${MAVEN_VERSION}/binaries/apache-maven-${MAVEN_VERSION}-bin.tar.gz"
    tar xzf "${TMPDIR:-/tmp}/apache-maven-${MAVEN_VERSION}-bin.tar.gz" -C "${TMPDIR:-/tmp}"
  fi
  MVN="${MVN_HOME}/bin/mvn"
fi

# --- Optionally set the version --------------------------------------------------
if [ "$#" -ge 1 ]; then
  echo "==> Setting project version to $1"
  "${MVN}" -q -B versions:set -DnewVersion="$1" -DgenerateBackupPoms=false
fi

VERSION="$(grep -m1 -oE '<version>[^<]+</version>' pom.xml | sed -E 's/<\/?version>//g')"

# --- Preflight: require usable credentials ---------------------------------------
if ! gcloud auth application-default print-access-token >/dev/null 2>&1; then
  echo "ERROR: no usable Application Default Credentials for Artifact Registry." >&2
  echo "       Run 'gcloud auth application-default login', or set GOOGLE_APPLICATION_CREDENTIALS" >&2
  echo "       to a service-account key holding roles/artifactregistry.writer on streak-maven." >&2
  exit 1
fi

echo "==> Deploying com.googlecode.objectify:objectify:${VERSION}"
echo "    to ${REPO_URL}"
echo "    Never overwrite a previously published version — bump the -streak-valkey-N suffix instead."

"${MVN}" -B -DskipTests deploy

echo "==> Published com.googlecode.objectify:objectify:${VERSION}"
echo "    Update the coordinate in MailFoo's MODULE.bazel and settings.gradle.kts to match."
