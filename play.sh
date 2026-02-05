#!/bin/bash

# Flexible game launcher
# Usage:
#   ./play.sh                           # 2v2, you + 3 random bots
#   ./play.sh striker goalie            # 2v2, you + striker + goalie + 1 random bot
#   ./play.sh striker goalie defender midfielder  # 2v2, all bots, server viz
#   ./play.sh -p 3 striker goalie       # 3v3, you + 2 provided + 3 random bots

PLAYERS=2

# Parse -p/--players option
while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--players)
            PLAYERS="$2"
            shift 2
            ;;
        *)
            break
            ;;
    esac
done

# Remaining args are agent names
AGENTS=("$@")
PROVIDED=${#AGENTS[@]}
TOTAL=$((PLAYERS * 2))

echo "Game: ${PLAYERS}v${PLAYERS} ($TOTAL players needed)"
echo "Provided agents: $PROVIDED"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PID_FILE="$SCRIPT_DIR/.football_server.pid"
CLIENT_PIDS_FILE="$SCRIPT_DIR/.football_clients.pid"

# Kill previous game started by this script (if any)
if [ -f "$PID_FILE" ]; then
    OLD_PID=$(cat "$PID_FILE")
    if kill -0 "$OLD_PID" 2>/dev/null; then
        echo "Stopping previous server (PID $OLD_PID)..."
        kill "$OLD_PID" 2>/dev/null
        sleep 0.3
    fi
    rm -f "$PID_FILE"
fi
if [ -f "$CLIENT_PIDS_FILE" ]; then
    while read -r pid; do
        kill "$pid" 2>/dev/null
    done < "$CLIENT_PIDS_FILE"
    rm -f "$CLIENT_PIDS_FILE"
fi

cleanup() {
    echo ""
    echo "Shutting down..."
    kill $SERVER_PID 2>/dev/null
    rm -f "$PID_FILE"
    if [ -f "$CLIENT_PIDS_FILE" ]; then
        while read -r pid; do
            kill "$pid" 2>/dev/null
        done < "$CLIENT_PIDS_FILE"
        rm -f "$CLIENT_PIDS_FILE"
    fi
    exit 0
}
trap cleanup EXIT INT TERM

if [ $PROVIDED -ge $TOTAL ]; then
    # All slots filled with bots - server shows visualization
    echo "All slots filled - server visualization mode"
    echo ""

    uv run python server.py --players "$PLAYERS" --viz &
    SERVER_PID=$!
    echo $SERVER_PID > "$PID_FILE"
    sleep 1

    # Connect all provided agents
    > "$CLIENT_PIDS_FILE"  # Clear file
    for i in $(seq 0 $((TOTAL - 1))); do
        AGENT=${AGENTS[$i]}
        uv run python client.py localhost --agent "$AGENT" &
        echo $! >> "$CLIENT_PIDS_FILE"
        echo "  Bot $((i + 1)): $AGENT"
    done

    echo ""
    echo "Game running. Close window or Ctrl+C to stop."
    wait $SERVER_PID
else
    # Need keyboard player - client shows visualization
    KEYBOARD_SLOTS=1
    BOTS_NEEDED=$((TOTAL - PROVIDED - KEYBOARD_SLOTS))

    echo "Adding keyboard player with visualization"
    if [ $BOTS_NEEDED -gt 0 ]; then
        echo "Adding $BOTS_NEEDED random bot(s) to fill slots"
    fi
    echo ""

    # Random bot types for filler
    RANDOM_BOTS=(chaser striker defender midfielder goalie)

    uv run python server.py --players "$PLAYERS" &
    SERVER_PID=$!
    echo $SERVER_PID > "$PID_FILE"
    sleep 1

    # Connect provided agents
    > "$CLIENT_PIDS_FILE"  # Clear file
    for i in $(seq 0 $((PROVIDED - 1))); do
        AGENT=${AGENTS[$i]}
        uv run python client.py localhost --agent "$AGENT" &
        echo $! >> "$CLIENT_PIDS_FILE"
        echo "  Bot $((i + 1)): $AGENT"
    done

    # Fill remaining with random bots
    for i in $(seq 1 $BOTS_NEEDED); do
        RAND_IDX=$((RANDOM % ${#RANDOM_BOTS[@]}))
        AGENT=${RANDOM_BOTS[$RAND_IDX]}
        uv run python client.py localhost --agent "$AGENT" &
        echo $! >> "$CLIENT_PIDS_FILE"
        echo "  Bot (random): $AGENT"
    done

    sleep 1
    echo ""
    echo "Controls: WASD=move, SPACE=kick, ESC=quit"
    echo ""

    # Connect keyboard player (foreground, with visualization)
    uv run python client.py localhost --keyboard
fi
