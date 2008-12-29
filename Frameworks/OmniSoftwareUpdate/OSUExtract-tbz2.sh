#!/bin/zsh -f

set -e

TBZ2_FILE=$1
if [ -z "$TBZ2_FILE" ]; then
  echo "No source file specified!"
fi

OUTPUT_DIR=$2
if [ -z "$OUTPUT_DIR" ]; then
  echo "No output directory specified!"
fi
if [ ! -d "$OUTPUT_DIR" ]; then
  echo "$OUTPUT_DIR doesn't exist!"
fi

cd "$OUTPUT_DIR"
bunzip2 < "$TBZ2_FILE" | tar xf -
