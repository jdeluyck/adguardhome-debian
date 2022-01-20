#!/bin/bash
set -x
set -e

# Architectures
ARCHS="i386 amd64 arm64 armhf"

# GnuPG key for signing
GPG_ID="B814C6C9ECB9207D506AB476F990F1A13176F005"


RELEASE_DIR="build/release"

# Repo config
REPO_DIR="repo"
SECTION="contrib"
PKG_DIR="pool/${SECTION}"
DIST_DIR="dists/stable"
SECTION_DIST_DIR="${DIST_DIR}/${SECTION}"

LAST_BUILD="LAST_BUILD"

TEAM="AdGuardTeam"
PROJECT="AdGuardHome"

PRJDIR=${PWD}


add_to_repo() {
  ARCH=${1}

  ARCH_BIN_DIST_DIR=${SECTION_DIST_DIR}/binary-${ARCH}
  mkdir -p ${REPO_DIR}/${ARCH_BIN_DIST_DIR}

  cp ${RELEASE_DIR}/adguardhome_${VERSION}_${ARCH}.deb ${REPO_DIR}/${PKG_DIR}

  cd ${REPO_DIR}

  # Create Packages/Packages.gz
  apt-ftparchive --arch ${ARCH} packages ${PKG_DIR} > ${ARCH_BIN_DIST_DIR}/Packages
  gzip -fk9 ${ARCH_BIN_DIST_DIR}/Packages

  # Create Contents/Contents.gz
  apt-ftparchive --arch ${ARCH} contents ${PKG_DIR} > ${SECTION_DIST_DIR}/Contents-${ARCH}
  gzip -fk9 ${SECTION_DIST_DIR}/Contents-${ARCH}

  # Create Releases
  apt-ftparchive --arch ${ARCH} release ${ARCH_BIN_DIST_DIR} > ${ARCH_BIN_DIST_DIR}/Release  

  cd ${PRJDIR}
}


VERSION=$(curl -L -s -H 'Accept: application/json' https://github.com/${TEAM}/${PROJECT}/releases/latest | jq -r '.tag_name | gsub("v";"")')

REBUILD_REPO=0

echo "Target version: ${VERSION}"

mkdir -p ${REPO_DIR}/${PKG_DIR}

for ARCH in ${ARCHS}; do
  echo "Building ${ARCH}..."
  # ARCH_BIN_DIST_DIR=${SECTION_DIST_DIR}/binary-${ARCH}

  LAST_BUILD_FILE="${LAST_BUILD}_${ARCH}"
  if [ -e ${LAST_BUILD_FILE} ]; then
    LAST_BUILD_VER=$(cat ${LAST_BUILD_FILE})
  else
    LAST_BUILD_VER="N/A"
  fi

  echo "Last build version: ${LAST_BUILD_VER}"

  if [ ${VERSION} == "${LAST_BUILD_VER}" ]; then
    echo "No new version for ${ARCH}, skipping"
    # exit 0
  else
    echo "Building new version"
    make VERSION=${VERSION} ARCH=${ARCH}
    if [ ${?} -eq 0 ]; then
      echo ${VERSION} > ${LAST_BUILD_FILE}

      add_to_repo ${ARCH}

      REBUILD_REPO=1
    else
      echo "Error building ${ARCH}"
    fi
  fi

done

if [ ${REBUILD_REPO} -ne 0 ]; then

  cd ${REPO_DIR}

  apt-ftparchive release -c ${PRJDIR}/release.conf ${DIST_DIR} > ${DIST_DIR}/Release

  # Sign
  gpg -a --yes --output ${DIST_DIR}/Release.gpg --local-user ${GPG_ID} --detach-sign ${DIST_DIR}/Release
  gpg -a --yes --clearsign --output ${DIST_DIR}/InRelease --local-user ${GPG_ID} --detach-sign ${DIST_DIR}/Release
fi