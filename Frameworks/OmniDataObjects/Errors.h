// Copyright 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniDataObjects/Errors.h 104581 2008-09-06 21:18:23Z kc $

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

#define ODOErrorWithInfo(error, code, description, reason, ...) _OBError(error, OMNI_BUNDLE_IDENTIFIER, code, __FILE__, __LINE__, NSLocalizedDescriptionKey, description, NSLocalizedFailureReasonErrorKey, (reason), ## __VA_ARGS__)
#define ODOError(error, code, description, reason, suggestion) ODOErrorWithInfo((error), (code), (description), (reason), NSLocalizedRecoverySuggestionErrorKey, (suggestion), nil)


extern NSString * const ODOSQLiteErrorDomain; // Underlying errors will be formed with this, using the SQLite return code and error message.

struct sqlite3;
extern void ODOSQLiteError(NSError **outError, int code, struct sqlite3 *sqlite);
