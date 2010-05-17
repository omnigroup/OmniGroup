// Copyright 2008, 2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniDataObjects/Errors.h>

#import <sqlite3.h>

RCS_ID("$Id$")

NSString * const ODOErrorDomain = @"com.omnigroup.framework.OmniDataObjects.ErrorDomain";

NSString * const ODOSQLiteErrorDomain = @"org.sqlite.sqlite3";

NSError *_ODOSQLiteError(NSError *underlyingError, int code, struct sqlite3 *sqlite)
{
    OBPRECONDITION(underlyingError == nil); // *outError should be nil
    OBPRECONDITION(sqlite);
    OBPRECONDITION(code != SQLITE_OK);
    
    //OBPRECONDITION(code == sqlite3_errcode(sqlite)); // Maybe we can avoid passing in the error code.
    // Nope.  If an error occurs during an update, the sqlite3_step can return a generic error and the sqlite3 struct has the specific error.
    
    // Get a more specific error if possible.
    if (code == SQLITE_ERROR) {
        int specific = sqlite3_errcode(sqlite);
        if (specific != SQLITE_OK && specific != SQLITE_ERROR)
            code = specific;
    }

    NSString *message;
    const char *messageUTF8String = sqlite3_errmsg(sqlite);
    if (messageUTF8String)
        message = [[NSString alloc] initWithUTF8String:messageUTF8String];
    else
        message = @"Null message from SQLite";
    
    NSDictionary *userInfo = [[NSDictionary alloc] initWithObjectsAndKeys:NSLocalizedDescriptionKey, message, nil];
    [message release];
    
    NSError *error = [NSError errorWithDomain:ODOSQLiteErrorDomain code:code userInfo:userInfo];
    [userInfo release];
    return error;
}

