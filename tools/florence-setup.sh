#!/bin/bash
# One-time setup of the Florence-2 chord reader (about 1-2 GB of downloads).
set -e
python3 -m venv "$HOME/.chordchart-florence"
"$HOME/.chordchart-florence/bin/pip" install --upgrade pip
"$HOME/.chordchart-florence/bin/pip" install torch torchvision pillow "transformers==5.19.0"
echo "setup done. start it with:  bash $(cd "$(dirname "$0")" && pwd)/florence-start.sh"
