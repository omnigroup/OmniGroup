// Copyright 2008-2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSError.h>
#import <OmniBase/NSError-OBUtilities.h>

extern NSErrorDomain const ODOErrorDomain;
extern NSErrorDomain const ODOSQLiteErrorDomain; // Underlying errors will be formed with this, using the SQLite return code and error message.
extern NSErrorUserInfoKey const ODODetailedErrorsKey; // If multiple errors occur in one operation, they are collected in an array and added with this key to the "top-level error" of the operation


extern NSErrorUserInfoKey const ODODetailedErrorsKey; // if multiple validation errors occur in one operation, they are collected in an array and added with this key to the "top-level error" of the operation

typedef NS_ERROR_ENUM(ODOErrorDomain, ODOError) {
    ODONoError = 0,

    ODOUnableToLoadModel,
    ODOUnableToConnectDatabase,
    ODOErrorDisconnectingFromDatabase,
    ODOUnableToCreateSchema,
    ODOUnableToCreateSQLStatement,
    ODOUnableToExecuteSQL,
    ODOUnableToSaveMetadata,
    ODOUnableToSave,
    ODOUnableToSaveTryReopen,
    ODOUnableToFetchFault,
    
    ODODeletePropagationFailed,
    ODOMultipleDeleteErrorsError,
    
    ODOUnableToFindObjectWithID,
    ODOUnableToFindObjectWithIDMultipleErrors,

    ODORequestedObjectIsScheduledForDeletion,
    
    // Validation
    ODORequiredValueNotPresentValidationError,
    ODOValueOfWrongClassValidationError,
};

#define ODOErrorWithInfo(error, code, description, suggestion, ...) _OBError(error, ODOErrorDomain, code, __FILE__, __LINE__, NSLocalizedDescriptionKey, description, NSLocalizedRecoverySuggestionErrorKey, (suggestion), ## __VA_ARGS__)

#define ODOError(error, code, description, reason) ODOErrorWithInfo((error), (code), (description), (reason), nil)

extern BOOL ODOMultipleDeleteError(NSError **outError, NSArray<NSError *> *errors);
extern BOOL ODOMultipleUnableToFindObjectWithIDError(NSError **outError, NSArray<NSError *> *errors);

struct sqlite3;
extern NSError *_ODOSQLiteError(NSError *underlyingError, int code, struct sqlite3 *sqlite);

#define ODOSQLiteError(outError, code, sqlite) do { \
    NSError **_outError = (outError); \
    OBASSERT(outError); \
    if (_outError) \
        *_outError = _ODOSQLiteError(*_outError, code, sqlite); \
} while(0)


#pragma mark -

@interface NSError (ODOExtensions)

- (BOOL)causedByMissingObject;

@end
