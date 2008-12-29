#!/bin/zsh -f

# Die on any error
set -e

# Report everything that happened into the error log (or the console log, up until we redirect stderr).
set -x

# The authorization framework doesn't allow collecting stderr, so we direct it to a file.
if [ -z "$REDIRECTED_STDERR" ]; then
    echo args: "$@"
    
    # The error log shouldn't overwrite; get this first
    ERRORS=$4
    if [ -x "$ERRORS" ]; then
            echo "$ERRORS already exists!"
            exit 4
    fi

    echo "Putting stderr in '$ERRORS'" 2>&1
    export REDIRECTED_STDERR=YES
    exec $0 "$@" 2> "$ERRORS"
fi

SOURCE=$1
if [ ! -x "$SOURCE" ]; then
	echo "$SOURCE doesn't exist!"
	exit 1
fi

# If this is what we are replacing, so it must exist already
DEST=$2
if [ ! -x "$DEST" ]; then
	echo "$DEST doesn't exist!"
	exit 2
fi

# We don't allow archiving to overwrite
ARCHIVE=$3
if [ -x "$ARCHIVE" ]; then
	echo "$ARCHIVE already exists!"
	exit 3
fi

# Adjust the ownership of the new copy to be the same as the original; if this tool is run with admin permissions.
if [ "$EUID" = "0" ]; then
	OLD_UID=`/usr/bin/stat -f "%u" "$DEST"`
	OLD_GID=`/usr/bin/stat -f "%g" "$DEST"`
	/usr/sbin/chown -R $OLD_UID:$OLD_GID "$SOURCE"
fi

/bin/mv "$DEST" "$ARCHIVE"
/bin/mv "$SOURCE" "$DEST"

exit 0
