// Copyright 2008, 2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

extern NSString * const ODODetailedErrorsKey; // if multiple validation errors occur in one operation, they are collected in an array and added with this key to the "top-level error" of the operation

enum {
    ODONoError = 0,
    
    ODOUnableToLoadModel,
    ODOUnableToConnectDatabase,
    ODOErrorDisconnectingFromDatabase,
    ODOUnableToCreateSchema,
    ODOUnableToCreateSQLStatement,
    ODOUnableToExecuteSQL,
    ODOUnableToSaveMetadata,
    ODOUnableToSave,
    ODOUnableToFetchFault,
    
    ODODeletePropagationFailed,
    
    // Validation
    ODORequiredValueNotPresentValidationError,
    ODOValueOfWrongClassValidationError,
};

extern NSString * const ODOErrorDomain;

#define ODOErrorWithInfo(error, code, description, suggestion, ...) _OBError(error, ODOErrorDomain, code, __FILE__, __LINE__, NSLocalizedDescriptionKey, description, NSLocalizedRecoverySuggestionErrorKey, (suggestion), ## __VA_ARGS__)
#define ODOError(error, code, description, reason) ODOErrorWithInfo((error), (code), (description), (reason), nil)

extern NSString * const ODOSQLiteErrorDomain; // Underlying errors will be formed with this, using the SQLite return code and error message.

struct sqlite3;
extern NSError *_ODOSQLiteError(NSError *underlyingError, int code, struct sqlite3 *sqlite);

#define ODOSQLiteError(outError, code, sqlite) do { \
    NSError **_outErorr = (outError); \
    OBASSERT(outError); \
    if (_outErorr) \
        *_outErorr = _ODOSQLiteError(*_outErorr, code, sqlite); \
} while(0)
