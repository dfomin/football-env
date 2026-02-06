#!/bin/bash

# Flexible game launcher
# Usage:
#   ./play.sh                           # 2v2, you + 3 random bots
#   ./play.sh -p 3                      # 3v3, you + 5 random bots
#   ./play.sh striker goalie defender   # 2v2, you + 3 named bots
#   ./play.sh -p 3 striker goalie       # 3v3, you + 2 named + 3 random bots
#   ./play.sh striker goalie defender midfielder  # 2v2, all bots, server viz

PLAYERS=2

# Parse -p/--players option (players per team, like main.py)
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

if [ $PROVIDED -ge $TOTAL ]; then
    USE_KEYBOARD=false
    echo "Game: ${PLAYERS}v${PLAYERS} ($TOTAL bots)"
else
    USE_KEYBOARD=true
    echo "Game: ${PLAYERS}v${PLAYERS} (you + $((TOTAL - 1)) AI)"
fi

PORT=8765
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PID_FILE="$SCRIPT_DIR/.football_server.pid"
CLIENT_PIDS_FILE="$SCRIPT_DIR/.football_clients.pid"

kill_port() {
    # Kill any process listening on the game port
    local pids
    pids=$(lsof -ti :$PORT 2>/dev/null)
    if [ -n "$pids" ]; then
        echo "Killing stale process(es) on port $PORT..."
        echo "$pids" | xargs kill 2>/dev/null
        sleep 0.5
        # Force kill if still alive
        pids=$(lsof -ti :$PORT 2>/dev/null)
        [ -n "$pids" ] && echo "$pids" | xargs kill -9 2>/dev/null
    fi
}

# Kill previous game
if [ -f "$CLIENT_PIDS_FILE" ]; then
    while read -r pid; do
        kill "$pid" 2>/dev/null
    done < "$CLIENT_PIDS_FILE"
    rm -f "$CLIENT_PIDS_FILE"
fi
kill_port
rm -f "$PID_FILE"

cleanup() {
    echo ""
    echo "Shutting down..."
    if [ -f "$CLIENT_PIDS_FILE" ]; then
        while read -r pid; do
            kill "$pid" 2>/dev/null
        done < "$CLIENT_PIDS_FILE"
        rm -f "$CLIENT_PIDS_FILE"
    fi
    kill_port
    rm -f "$PID_FILE"
    exit 0
}
trap cleanup EXIT INT TERM

# Random bot types for filler
RANDOM_BOTS=(chaser striker defender midfielder goalie)

if [ "$USE_KEYBOARD" = false ]; then
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
    # Keyboard mode - client shows visualization
    BOTS_NEEDED=$((TOTAL - PROVIDED - 1))

    if [ $BOTS_NEEDED -gt 0 ]; then
        echo "Adding $BOTS_NEEDED random bot(s) to fill slots"
    fi
    echo ""

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
    if [ $BOTS_NEEDED -gt 0 ]; then
        for i in $(seq 1 $BOTS_NEEDED); do
            RAND_IDX=$((RANDOM % ${#RANDOM_BOTS[@]}))
            AGENT=${RANDOM_BOTS[$RAND_IDX]}
            uv run python client.py localhost --agent "$AGENT" &
            echo $! >> "$CLIENT_PIDS_FILE"
            echo "  Bot (random): $AGENT"
        done
    fi

    sleep 1
    echo ""
    echo "Controls: WASD=move, SPACE=kick, ESC=quit"
    echo ""

    # Connect keyboard player (foreground, with visualization)
    uv run python client.py localhost --keyboard
fi
