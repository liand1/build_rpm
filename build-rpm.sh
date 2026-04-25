#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAME="tngs-bootstrap"
VERSION="0.2.4"
TOPDIR="${ROOT_DIR}/out"
SOURCEDIR="${TOPDIR}/SOURCES"
SPECDIR="${TOPDIR}/SPECS"
BUILDDIR="${TOPDIR}/BUILD"
RPMDIR="${TOPDIR}/RPMS"
SRPMDIR="${TOPDIR}/SRPMS"

echo "[build] preparing rpmbuild tree under ${TOPDIR}"
mkdir -p "${SOURCEDIR}" "${SPECDIR}" "${BUILDDIR}" "${RPMDIR}" "${SRPMDIR}"

echo "[build] creating source tarball"
TMP_SRC="${SOURCEDIR}/${NAME}-${VERSION}"
rm -rf "${TMP_SRC}"
mkdir -p "${TMP_SRC}"
cp -r "${ROOT_DIR}/scripts" "${TMP_SRC}/scripts"
cp -r "${ROOT_DIR}/images" "${TMP_SRC}/images"
cp -r "${ROOT_DIR}/rpm" "${TMP_SRC}/rpm"
cp "${ROOT_DIR}/build-rpm.sh" "${TMP_SRC}/build-rpm.sh"
cp "${ROOT_DIR}/readme.md" "${TMP_SRC}/README.md"

tar -C "${SOURCEDIR}" -czf "${SOURCEDIR}/${NAME}-${VERSION}.tar.gz" "${NAME}-${VERSION}"
rm -rf "${TMP_SRC}"

echo "[build] copying spec file"
cp "${ROOT_DIR}/rpm/${NAME}.spec" "${SPECDIR}/"

echo "[build] running rpmbuild"
rpmbuild -bb "${SPECDIR}/${NAME}.spec" \
  --define "_topdir ${TOPDIR}"

echo "[build] done. output:"
find "${RPMDIR}" -type f -name "*.rpm" -print
