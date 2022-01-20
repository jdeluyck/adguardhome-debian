#!/bin/bash
DEBUG=0

# Architectures
ARCHS="i386 amd64 arm64 armhf"

# GnuPG key for signing
GPG_ID="4E317DD331F621853D7D0E294C57F7B442CA12CF"

# Release dir
RELEASE_DIR="build/release"

# Repo config
REPO_DIR="repo"
SECTION="contrib"
PKG_DIR="pool/${SECTION}"
DIST_DIR="dists/stable"
SECTION_DIST_DIR="${DIST_DIR}/${SECTION}"

# Last build file prefix
LAST_BUILD="LAST_BUILD"

# Github Repo location
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
  log info "Creating ${ARCH} Packages/Packages.gz"
  apt-ftparchive --arch ${ARCH} packages ${PKG_DIR} > ${ARCH_BIN_DIST_DIR}/Packages
  gzip -fk9 ${ARCH_BIN_DIST_DIR}/Packages

  # Create Contents/Contents.gz
  log info "Creating ${ARCH} Contents/Contents.gz"
  apt-ftparchive --arch ${ARCH} contents ${PKG_DIR} > ${SECTION_DIST_DIR}/Contents-${ARCH}
  gzip -fk9 ${SECTION_DIST_DIR}/Contents-${ARCH}

  # Create Releases
  log info "Creating ${ARCH} Release"
  apt-ftparchive --arch ${ARCH} release ${ARCH_BIN_DIST_DIR} > ${ARCH_BIN_DIST_DIR}/Release  

  cd ${PRJDIR}
}

log() {
  LEVEL=${1^^}; shift
  TEXT=${@}


  if [ ${LEVEL} == "INFO" ]; then
    if [ ${DEBUG} -eq 1 ]; then
      echo "${LEVEL}: ${TEXT}"
    fi
  else
    echo "${LEVEL}: ${TEXT}"
  fi
}

VERSION=$(curl -L -s -H 'Accept: application/json' https://github.com/${TEAM}/${PROJECT}/releases/latest | jq -r '.tag_name | gsub("v";"")')

REBUILD_REPO=0

log info "Target version: ${VERSION}"

mkdir -p ${REPO_DIR}/${PKG_DIR}

for ARCH in ${ARCHS}; do
  log info "Building ${ARCH}..."

  LAST_BUILD_FILE="${LAST_BUILD}_${ARCH}"
  if [ -e ${LAST_BUILD_FILE} ]; then
    LAST_BUILD_VER=$(cat ${LAST_BUILD_FILE})
  else
    LAST_BUILD_VER="N/A"
  fi

  log info "Last build version: ${LAST_BUILD_VER}"

  if [ ${VERSION} == "${LAST_BUILD_VER}" ]; then
    log info "No new version for ${ARCH}, skipping"
  else
    log info "Building new version"
    make VERSION=${VERSION} ARCH=${ARCH} >> /dev/null 
    if [ ${?} -eq 0 ]; then
      echo ${VERSION} > ${LAST_BUILD_FILE}

      add_to_repo ${ARCH}

      REBUILD_REPO=1
    else
      log error "Error building ${ARCH}"
    fi
  fi

done

if [ ${REBUILD_REPO} -ne 0 ]; then

  cd ${REPO_DIR}
  log info "Creating new repo Release file"
  apt-ftparchive release -c ${PRJDIR}/release.conf ${DIST_DIR} > ${DIST_DIR}/Release

  # Sign
  log info "Singing Release files"
  gpg -a --yes --output ${DIST_DIR}/Release.gpg --local-user ${GPG_ID} --detach-sign ${DIST_DIR}/Release
  gpg -a --yes --clearsign --output ${DIST_DIR}/InRelease --local-user ${GPG_ID} --detach-sign ${DIST_DIR}/Release

  log info "Uploading to B2"
  B2_ACCOUNT_INFO=~/.b2_deb_pkg backblaze-b2 sync --delete --replaceNewer --noProgress ~/source/adguardhome-debian/repo/ b2://deb-packages/ > /dev/null
fi
