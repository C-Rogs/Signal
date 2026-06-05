#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_DIR="$ROOT/Signal"
DEVICE_ID="00008140-001E34E10A01801C"
ONLY_TESTING="SignalTests/CoachUATDeviceTests/testCoachUATSmokeOnDevice"

cd "$PROJECT_DIR"

DEST="platform=iOS,id=${DEVICE_ID}"

echo "Building Signal for device ${DEVICE_ID}..."
xcodebuild -scheme Signal -destination "$DEST" build

echo "Running coach UAT smoke on device (4 FM prompts, ~1 minute)."
echo "Full 15-prompt evaluation: Diagnostics > Coach evaluation on the phone."

set +e
xcodebuild -scheme Signal \
  -destination "$DEST" \
  -parallel-testing-enabled NO \
  test -only-testing:"${ONLY_TESTING}" \
  2>&1 | tee /tmp/signal-coach-uat-test.log
TEST_EXIT=${PIPESTATUS[0]}
set -e

echo ""
grep -E 'coach_uat_report json=|coach_uat id=' /tmp/signal-coach-uat-test.log | tail -20 || true

XCRESULT_PATH="$(ls -td ~/Library/Developer/Xcode/DerivedData/Signal-*/Logs/Test/*.xcresult 2>/dev/null | head -1 || true)"
if [[ -n "${XCRESULT_PATH}" && -d "${XCRESULT_PATH}" ]]; then
  echo ""
  echo "Latest xcresult: ${XCRESULT_PATH}"
  xcrun xcresulttool get test-results summary --path "${XCRESULT_PATH}" 2>/dev/null || true
fi

if [[ "${TEST_EXIT}" -ne 0 ]]; then
  echo "Coach UAT device tests failed with exit code ${TEST_EXIT}" >&2
  exit "${TEST_EXIT}"
fi

echo "Coach UAT device tests passed."
