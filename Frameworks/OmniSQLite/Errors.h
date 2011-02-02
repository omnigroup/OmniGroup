// Copyright 2011 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

@class NSError, NSString;

extern NSString * const OSLSQLErrorDomain; // Underlying errors will be formed with this, using the SQLite return code and error message.

struct sqlite3;
extern NSError *_OSLSQLError(NSError *underlyingError, int code, struct sqlite3 *sqlite);

#define OSLSQLError(outError, code, sqlite) do { \
    NSError **_outError = (outError); \
    OBASSERT(outError); \
    if (_outError) \
        *_outError = _OSLSQLError(*_outError, code, sqlite); \
} while(0)
