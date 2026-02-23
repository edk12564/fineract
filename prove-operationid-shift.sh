#!/bin/bash
#
# prove-operationid-shift.sh
#
# Proves that OpenAPI operationId deduplication numbers are unstable.
# Adding a single new retrieveAll() endpoint causes existing dedup numbers to shift,
# which breaks any generated client code (including Cucumber tests) that
# references these numbered method names.
#
# The test subject is /v1/journalentries — its retrieveAll() is called 5 times
# in JournalEntriesStepDef.java via the generated method retrieveAll1().
#
# Usage: ./prove-operationid-shift.sh
#
# Requirements: Must be run from the Fineract project root.
# Takes ~5-10 minutes (two Gradle builds).
# DummyRetrieveAllTestEndpoint.java.disabled must exist in the journal entry api package.

set -e

API_DIR="fineract-provider/src/main/java/org/apache/fineract/accounting/journalentry/api"
DUMMY_JAVA="$API_DIR/DummyRetrieveAllTestEndpoint.java"
DUMMY_DISABLED="$API_DIR/DummyRetrieveAllTestEndpoint.java.disabled"
SPEC_FILE="fineract-provider/build/resources/main/static/fineract.yaml"

TARGET_PATH="/v1/journalentries:"
TARGET_LABEL="Journal Entries (/v1/journalentries)"

# Extract operationId for the target path. Uses grep -A 30 because some endpoints
# have long description blocks between the path and the operationId line.
get_opid() {
    grep -A 30 "$TARGET_PATH" "$SPEC_FILE" | grep "operationId:" | head -1 | awk '{print $2}'
}

echo "============================================"
echo "  OpenAPI operationId Shift Proof"
echo "============================================"
echo ""
echo "  Target: $TARGET_LABEL"
echo "  Cucumber usage: JournalEntriesStepDef.java (5 call sites)"
echo ""

# ---- Ensure dummy is disabled before we start ----
if [ -f "$DUMMY_JAVA" ]; then
    mv "$DUMMY_JAVA" "$DUMMY_DISABLED"
fi

if [ ! -f "$DUMMY_DISABLED" ]; then
    echo "ERROR: $DUMMY_DISABLED not found."
    exit 1
fi

# ---- Build WITHOUT the dummy endpoint ----
echo "[1/4] Building OpenAPI spec WITHOUT dummy endpoint..."
./gradlew :fineract-provider:resolve --quiet 2>&1 | tail -3

BEFORE_OPID=$(get_opid)
BEFORE_COUNT=$(grep -c "operationId: retrieveAll" "$SPEC_FILE")
echo "  operationId: $BEFORE_OPID  (total retrieveAll count: $BEFORE_COUNT)"
echo ""

# ---- Build WITH the dummy endpoint ----
echo "[2/4] Enabling dummy endpoint..."
mv "$DUMMY_DISABLED" "$DUMMY_JAVA"

echo "[3/4] Building OpenAPI spec WITH dummy endpoint..."
./gradlew :fineract-provider:resolve --quiet 2>&1 | tail -3

AFTER_OPID=$(get_opid)
AFTER_COUNT=$(grep -c "operationId: retrieveAll" "$SPEC_FILE")
echo "  operationId: $AFTER_OPID  (total retrieveAll count: $AFTER_COUNT)"
echo ""

# ---- Cleanup ----
echo "[4/4] Disabling dummy endpoint..."
mv "$DUMMY_JAVA" "$DUMMY_DISABLED"
echo ""

# ---- Results ----
echo "============================================"
echo "  RESULTS"
echo "============================================"
echo ""
echo "  $TARGET_LABEL"
echo "    Before (without dummy): $BEFORE_OPID"
echo "    After  (with dummy):    $AFTER_OPID"
echo ""

if [ "$BEFORE_OPID" != "$AFTER_OPID" ]; then
    echo "  PROVEN: operationId shifted from $BEFORE_OPID to $AFTER_OPID"
    echo ""
    echo "  JournalEntriesStepDef.java calls ${BEFORE_OPID//_/}() in 5 places."
    echo "  After the shift, that method would silently hit a DIFFERENT endpoint."
else
    echo "  UNEXPECTED: The operationId did not change."
fi
