#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAME="tngs-bootstrap"
VERSION="0.3.7"
TOPDIR="${ROOT_DIR}/out"
SOURCEDIR="${TOPDIR}/SOURCES"
SPECDIR="${TOPDIR}/SPECS"
BUILDDIR="${TOPDIR}/BUILD"
RPMDIR="${TOPDIR}/RPMS"
SRPMDIR="${TOPDIR}/SRPMS"
WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/${NAME}.XXXXXX")"

cleanup() {
  rm -rf "${WORKDIR}"
}
trap cleanup EXIT

echo "[build] preparing rpmbuild tree under ${TOPDIR}"
mkdir -p "${SOURCEDIR}" "${SPECDIR}" "${BUILDDIR}" "${RPMDIR}" "${SRPMDIR}"

echo "[build] creating source tarball"
TMP_SRC="${WORKDIR}/${NAME}-${VERSION}"
rm -f "${SOURCEDIR}/${NAME}-${VERSION}.tar.gz"
mkdir -p "${TMP_SRC}"
cp -r "${ROOT_DIR}/scripts" "${TMP_SRC}/scripts"
cp -r "${ROOT_DIR}/sql" "${TMP_SRC}/sql"
cp -r "${ROOT_DIR}/rpm" "${TMP_SRC}/rpm"
cp "${ROOT_DIR}/build-rpm.sh" "${TMP_SRC}/build-rpm.sh"
cp "${ROOT_DIR}/readme.md" "${TMP_SRC}/README.md"

tar -C "${WORKDIR}" -czf "${SOURCEDIR}/${NAME}-${VERSION}.tar.gz" "${NAME}-${VERSION}"
rm -rf "${TMP_SRC}"

echo "[build] copying Docker image archives as explicit RPM sources"
cp "${ROOT_DIR}/images/mysql_latest.tar" "${SOURCEDIR}/mysql_latest.tar"
cp "${ROOT_DIR}/images/redis_latest.tar" "${SOURCEDIR}/redis_latest.tar"
cp "${ROOT_DIR}/images/tngs-server-prod-1.0.0.tar" "${SOURCEDIR}/tngs-server-prod-1.0.0.tar"

echo "[build] copying spec file"
cp "${ROOT_DIR}/rpm/${NAME}.spec" "${SPECDIR}/"

echo "[build] running rpmbuild"
rpmbuild -bb "${SPECDIR}/${NAME}.spec" \
  --define "_topdir ${TOPDIR}"

echo "[build] done. output:"
find "${RPMDIR}" -type f -name "*.rpm" -print

if command -v rpm >/dev/null 2>&1; then
  RPM_FILE="$(find "${RPMDIR}" -type f -name "${NAME}-${VERSION}-*.noarch.rpm" | head -n 1)"
  if [[ -n "${RPM_FILE}" ]]; then
    echo "[build] rpm size:"
    ls -lh "${RPM_FILE}"
    echo "[build] bundled image files:"
    rpm -qpl "${RPM_FILE}" | grep '/images/' || true
    echo "[build] bundled sql files:"
    rpm -qpl "${RPM_FILE}" | grep '/sql/' || true
  fi
fi
