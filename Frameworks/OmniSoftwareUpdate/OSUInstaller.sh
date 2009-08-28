#!/bin/zsh -f

# Die on any error
set -e

# Report everything that happened into the error log (or the console log, up until we redirect stderr).
set -x

# The authorization framework doesn't allow collecting stderr, so we direct it to a file.
if [ -n "$3" ]; then
    # The error log shouldn't overwrite; get this first
    ERRORS=$3
    if [ -x "$ERRORS" ]; then
            echo "$ERRORS already exists!"
            exit 4
    fi

    echo "Putting stderr in '$ERRORS'" >&2
    exec 2> "$ERRORS"
fi

echo "args: $*" >&2

SOURCE=$1
DEST=$2
shift 3

if [ ! -x "$SOURCE" ]; then
	echo "$SOURCE doesn't exist!"
	exit 1
fi

if [ "x$1" = "x-u" ]; then
	CHOWN="$2"
	shift 2
fi

if [ "x$1" = "x-a" ]; then
	ARCHIVE_FROM="$2"
	ARCHIVE_TO="$3"
        shift 3
	
	# We don't allow archiving to overwrite
	if [ -x "$ARCHIVE_TO" ]; then
		echo "$ARCHIVE_TO already exists!"
		exit 3
	fi
	
	# This is what we are archiving, so it must exist already
	if [ ! -x "$ARCHIVE_FROM" ]; then
		echo "$ARCHIVE_FROM doesn't exist!"
		exit 2
	fi
fi


# Adjust the ownership of the new copy to be the same as the original (if this tool is run with admin permissions)
if [ ! -z "$CHOWN" ]; then
	/usr/sbin/chown -R "$CHOWN" "$SOURCE"
fi

# Archive the old copy if requested
if [ ! -z "$ARCHIVE_TO" ]; then
	/bin/mv -n "$ARCHIVE_FROM" "$ARCHIVE_TO"
fi

# Install the new copy
/bin/mv -n "$SOURCE" "$DEST"

exit 0
