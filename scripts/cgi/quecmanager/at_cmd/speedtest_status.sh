#!/bin/sh
# =============================================================================
# speedtest_status.sh — CGI Endpoint: Speedtest Status / Progress
# =============================================================================
# Polls the current speedtest state. Returns one of:
#   - idle:     No test running, no cached result
#   - running:  Test in progress, includes current progress line
#   - complete: Test finished, includes full result
#   - error:    Something went wrong
#
# Endpoint: GET /cgi-bin/quecmanager/at_cmd/speedtest_status.sh
#
# Install location: /www/cgi-bin/quecmanager/at_cmd/speedtest_status.sh
# =============================================================================

# --- Configuration -----------------------------------------------------------
PID_FILE="/tmp/qmanager_speedtest.pid"
OUTPUT_FILE="/tmp/qmanager_speedtest_output"
RESULT_FILE="/tmp/qmanager_speedtest_result.json"

# --- HTTP Headers ------------------------------------------------------------
echo "Content-Type: application/json"
echo "Cache-Control: no-cache"
echo "Access-Control-Allow-Origin: *"
echo "Access-Control-Allow-Methods: GET, OPTIONS"
echo "Access-Control-Allow-Headers: Content-Type"
echo ""

# --- Handle CORS preflight ---------------------------------------------------
if [ "$REQUEST_METHOD" = "OPTIONS" ]; then
    exit 0
fi

# =============================================================================
# STATE DETECTION
# =============================================================================

# Helper: extract "type" field from a JSON line (no jq on OpenWRT)
get_type() {
    echo "$1" | sed -n 's/.*"type"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p'
}

# Case 1: PID file exists — test may be running or just finished
if [ -f "$PID_FILE" ]; then
    SPEEDTEST_PID=$(cat "$PID_FILE" 2>/dev/null)

    if [ -n "$SPEEDTEST_PID" ] && kill -0 "$SPEEDTEST_PID" 2>/dev/null; then
        # =====================================================================
        # RUNNING — process is alive, grab latest progress line
        # =====================================================================
        if [ -f "$OUTPUT_FILE" ] && [ -s "$OUTPUT_FILE" ]; then
            LAST_LINE=$(tail -1 "$OUTPUT_FILE" 2>/dev/null)
            LINE_TYPE=$(get_type "$LAST_LINE")

            # Validate: the line should start with { and be parseable
            case "$LAST_LINE" in
                "{"*)
                    # Determine phase from the type field
                    case "$LINE_TYPE" in
                        testStart) PHASE="initializing" ;;
                        ping)      PHASE="ping" ;;
                        download)  PHASE="download" ;;
                        upload)    PHASE="upload" ;;
                        *)         PHASE="running" ;;
                    esac
                    printf '{"status":"running","phase":"%s","progress":%s}\n' "$PHASE" "$LAST_LINE"
                    ;;
                *)
                    # Output file exists but last line isn't valid JSON yet
                    echo '{"status":"running","phase":"initializing","progress":null}'
                    ;;
            esac
        else
            # Process started but hasn't written output yet
            echo '{"status":"running","phase":"initializing","progress":null}'
        fi
        exit 0
    else
        # =================================================================
        # JUST FINISHED — process is dead, harvest result
        # =================================================================
        rm -f "$PID_FILE"

        if [ -f "$OUTPUT_FILE" ] && [ -s "$OUTPUT_FILE" ]; then
            LAST_LINE=$(tail -1 "$OUTPUT_FILE" 2>/dev/null)
            LINE_TYPE=$(get_type "$LAST_LINE")

            if [ "$LINE_TYPE" = "result" ]; then
                # Save the final result for future reference
                echo "$LAST_LINE" > "$RESULT_FILE"
                printf '{"status":"complete","result":%s}\n' "$LAST_LINE"
            else
                # Process exited but last line isn't a result — likely crashed
                # Check if there's a result line anywhere in the output
                RESULT_LINE=$(grep '"type":"result"' "$OUTPUT_FILE" 2>/dev/null | tail -1)
                if [ -n "$RESULT_LINE" ]; then
                    echo "$RESULT_LINE" > "$RESULT_FILE"
                    printf '{"status":"complete","result":%s}\n' "$RESULT_LINE"
                else
                    echo '{"status":"error","error":"speedtest_failed","detail":"Process exited without producing results"}'
                fi
            fi
            # Clean up the (potentially large) progress output file
            rm -f "$OUTPUT_FILE"
        else
            echo '{"status":"error","error":"speedtest_failed","detail":"Process exited with no output"}'
        fi
        exit 0
    fi
fi

# Case 2: No PID file — check for cached result from previous run
if [ -f "$RESULT_FILE" ] && [ -s "$RESULT_FILE" ]; then
    CACHED_RESULT=$(cat "$RESULT_FILE" 2>/dev/null)
    printf '{"status":"complete","result":%s}\n' "$CACHED_RESULT"
    exit 0
fi

# Case 3: Nothing — no test running, no previous result
echo '{"status":"idle"}'
