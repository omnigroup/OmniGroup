#!/bin/zsh -f

# Die on any error
set -e

# The authorization framework doesn't allow collecting stderr, so we direct it to a file.
if [ -n "$3" ]; then
    # The error log shouldn't overwrite; get this first
    ERRORS=$3
    if [ -e "$ERRORS" ]; then
            echo "$ERRORS already exists!"
            exit 4
    fi

    echo "Putting stderr in '$ERRORS'" >&2
    exec 2> "$ERRORS"
    exec 1>&2
fi


echo "args: $*"
id

SOURCE=$1
DEST=$2
shift 3

if [ ! -r "$SOURCE" ]; then
	echo "$SOURCE doesn't exist!" >&2
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
	if [ -e "$ARCHIVE_TO" ]; then
		echo "$ARCHIVE_TO already exists!" >&2
		exit 3
	fi
	
	# This is what we are archiving, so it must exist already
	if [ ! -e "$ARCHIVE_FROM" ]; then
		echo "$ARCHIVE_FROM doesn't exist!" >&2
		exit 2
	fi
fi

if [ "x$1" = "x-am" ]; then
	CHMOD_ARCHIVE="$2"
	shift 2
fi

if [ "x$1" = "x-f" ]; then
        CHFLAGS="$2"
        shift 2
        
        if [ ! -z "$ARCHIVE_FROM" ]; then
            echo "Removing flags from $ARCHIVE_FROM"
            /usr/bin/chflags nouchg,noschg "$ARCHIVE_FROM"
        fi
fi

# Adjust the ownership of the new copy to be the same as the original (if this tool is run with admin permissions)
if [ ! -z "$CHOWN" ]; then
        echo "Setting ownership ($CHOWN) of $SOURCE"
	/usr/sbin/chown -R "$CHOWN" "$SOURCE"
fi

# Archive the old copy if requested
if [ ! -z "$ARCHIVE_TO" ]; then
        echo "Moving old copy aside: $ARCHIVE_FROM -> $ARCHIVE_TO"
        if [ ! -z "$CHMOD_ARCHIVE" ]; then
            echo "  Making it writable"
            /bin/chmod a+wx "$ARCHIVE_FROM" || true
        fi
	/bin/ls -leo@d "$ARCHIVE_FROM" "$ARCHIVE_TO:h" "$ARCHIVE_TO" || true
	/bin/mv -n "$ARCHIVE_FROM" "$ARCHIVE_TO"
        if [ ! -z "$CHMOD_ARCHIVE" ]; then
            echo "  Restoring original file mode to $CHMOD_ARCHIVE"
            /bin/chmod "$CHMOD_ARCHIVE" "$ARCHIVE_TO" || true
        fi
fi

# Install the new copy
echo "Moving new version into place: $SOURCE -> $DEST"
/bin/ls -leo@d "$SOURCE" "$DEST:h" "$DEST" || true
/bin/mv -n "$SOURCE" "$DEST"

# Set flags (probably uchg)
if [ ! -z "$CHFLAGS" ]; then
        echo "Applying flags ($CHFLAGS) to $DEST"
        /usr/bin/chflags "$CHFLAGS" "$DEST"
fi

echo "Installer script was successful."
/bin/ls -leo@d "$DEST" || true

exit 0
