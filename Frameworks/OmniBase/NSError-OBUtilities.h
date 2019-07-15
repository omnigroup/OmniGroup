// Copyright 2005-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.


// This contains the non ObjC extensions to NSError, useful for including them in Spotlight/QuickLook plugins w/o poluting the global ObjC namespace.

#if defined(__cplusplus)
extern "C" {
#endif

#import <Foundation/NSObjCRuntime.h>
#import <OmniBase/macros.h>

NS_ASSUME_NONNULL_BEGIN

@class NSString, NSError;

extern NSErrorDomain const OBErrorDomain;
extern NSErrorUserInfoKey const OBFileNameAndNumberErrorKey;

typedef NS_ERROR_ENUM(OBErrorDomain, OBError) {
    /* skip code zero since that is often defined to be 'no error' */
    OBErrorChained = 1, // An error wrapping another, just to not another source location the error passed through
    OBErrorMissing = 2, // A fallback error when we notice a bug where we are returning NO/nil to signal error, but haven't filled in the error yet.
};

extern NSError *_OBWrapUnderlyingError(NSError * _Nullable underlyingError, NSString *domain, NSInteger code, const char *fileName, unsigned int line, NSString * _Nullable firstKey, ...) NS_REQUIRES_NIL_TERMINATION;
    
#define _OBError(outError, domain, code, fileName, line, firstKey, ...) do { \
    __typeof__(outError) _outError = (outError); \
    if (_outError) \
        *_outError = _OBWrapUnderlyingError(*_outError, domain, code, fileName, line, firstKey, ## __VA_ARGS__); \
} while(0)
    
// Stacks another error on the input that simple records the calling code.  This can help establish the chain of failure when a callsite just fails because something else failed, without the overhead of adding another error code for that specific site.
#define OBChainError(error) _OBError(error, OBErrorDomain, OBErrorChained, __FILE__, __LINE__, nil)
extern NSError * _Nullable OBFirstUnchainedError(NSError * _Nullable error);

extern NSError *_OBChainedError(NSError *error, const char *fileName, unsigned line);
#define OBChainedError(error) _OBChainedError(error, __FILE__, __LINE__)

#define OBMissingError(outError, message) _OBError(outError, OBErrorDomain, OBErrorMissing, __FILE__, __LINE__, NSLocalizedDescriptionKey, (message), nil)

#define OBUserCancelledError(outError) _OBError(outError, NSCocoaErrorDomain, NSUserCancelledError, __FILE__, __LINE__, nil)
    
// Unlike the other routines in this file, but like all the other Foundation routines, this takes its key-value pairs with each value followed by its key.  The disadvantage to this is that you can't easily have runtime-ignored values (the nil value is a terminator rather than being skipped).
extern NSError *_OBErrorWithErrnoObjectsAndKeys(int errno_value, const char * _Nullable function, NSString * _Nullable argument, NSString * _Nullable localizedDescription, ...) NS_REQUIRES_NIL_TERMINATION;
#define OBErrorWithErrnoObjectsAndKeys(outError, errno_value, function, argument, localizedDescription, ...) do { \
    OB_AUTORELEASING NSError **_outError = (outError); \
    OBASSERT(!_outError || !*_outError); /*no underlying error support*/ \
    if (_outError) \
        *_outError = _OBErrorWithErrnoObjectsAndKeys(errno_value, function, argument, localizedDescription, ## __VA_ARGS__); \
} while(0)
    
#define OBErrorWithErrno(error, errno_value, function, argument, localizedDescription) OBErrorWithErrnoObjectsAndKeys(error, errno_value, function, argument, localizedDescription, nil)

/* This is handy for implementors of +setUserInfoValueProviderForDomain:provider: */
enum OBErrorWellKnownInfoKey {
    OBErrorKeyUnknown,
    OBErrorKeyDescription,    // -localizedDescription, NSLocalizedDescriptionKey
    OBErrorKeyFailureReason,  // -localizedFailureReason, NSLocalizedFailureReasonErrorKey
    OBErrorKeyHelpAnchor,     // -helpAnchor, NSHelpAnchorErrorKey
    OBErrorKeyRecoverySuggestion,  // -localizedRecoverySuggestion, NSLocalizedRecoverySuggestionErrorKey
};
enum OBErrorWellKnownInfoKey OBErrorWellKnownInfoKey(NSString *key);

NS_ASSUME_NONNULL_END

#if defined(__cplusplus)
} // extern "C"
#endif
