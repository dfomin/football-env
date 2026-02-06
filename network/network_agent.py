"""Server-side network agent wrapper."""

import threading
from typing import Optional, TYPE_CHECKING

from agents.base import BaseAgent, Action

if TYPE_CHECKING:
    from game.state import GameState
    import websockets


class NetworkAgent(BaseAgent):
    """
    Server-side agent wrapper that communicates with a remote client.

    Implements the BaseAgent interface, sending state to the remote client
    and receiving actions back via WebSocket.
    """

    def __init__(
        self,
        team_id: int,
        player_id: int,
        websocket: 'websockets.WebSocketServerProtocol',
    ):
        super().__init__(team_id, player_id)
        self.websocket = websocket
        self._pending_action: Optional[Action] = None
        self._lock = threading.Lock()

    def set_pending_action(self, action: Action) -> None:
        """Set the pending action received from the client."""
        with self._lock:
            self._pending_action = action

    def clear_pending_action(self) -> None:
        """Clear the pending action."""
        with self._lock:
            self._pending_action = None

    def get_action(self, state: 'GameState') -> Action:
        """
        Get action for the current game state.

        This is called synchronously by the game engine. Since network
        communication is async, we return the previously received action
        or a default action if none is available.

        The server should have already sent the state and received the
        action before this is called.
        """
        with self._lock:
            if self._pending_action is not None:
                return self._pending_action
        # Default action if no response received
        return Action(0.0, 0.0, False)

    def is_connected(self) -> bool:
        """Check if the websocket is still connected."""
        # websockets 12+ uses close_code (None means still open)
        return getattr(self.websocket, 'close_code', None) is None

    def reset(self) -> None:
        """Called when game resets (after goal scored)."""
        with self._lock:
            self._pending_action = None
