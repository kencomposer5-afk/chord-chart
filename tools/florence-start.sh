#!/bin/bash
# Starts the Florence-2 chord reader on http://localhost:8765 (keep the window open while using the app).
exec "$HOME/.chordchart-florence/bin/python" "$(cd "$(dirname "$0")" && pwd)/florence-server.py"
