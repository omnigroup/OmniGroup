// Copyright 2005-2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$


// This contains the non ObjC extensions to NSError, useful for including them in Spotlight/QuickLook plugins w/o poluting the global ObjC namespace.

#if defined(__cplusplus)
extern "C" {
#endif

#import <Foundation/NSObjCRuntime.h>
#import <OmniBase/macros.h>

@class NSString, NSError;

extern NSString * const OBErrorDomain;
extern NSString * const OBFileNameAndNumberErrorKey;

enum {
    OBErrorChained = 1,  /* skip code zero since that is often defined to be 'no error' */
};

extern NSError *_OBWrapUnderlyingError(NSError *underlyingError, NSString *domain, NSInteger code, const char *fileName, unsigned int line, NSString *firstKey, ...) NS_REQUIRES_NIL_TERMINATION;
    
#define _OBError(outError, domain, code, fileName, line, firstKey, ...) do { \
    OB_AUTORELEASING NSError **_outError = (outError); \
    if (_outError) \
        *_outError = _OBWrapUnderlyingError(*_outError, domain, code, fileName, line, firstKey, ## __VA_ARGS__); \
} while(0)
    
// Stacks another error on the input that simple records the calling code.  This can help establish the chain of failure when a callsite just fails because something else failed, without the overhead of adding another error code for that specific site.
#define OBChainError(error) _OBError(error, OBErrorDomain, OBErrorChained, __FILE__, __LINE__, nil)
extern NSError *OBFirstUnchainedError(NSError *error);

extern NSError *_OBChainedError(NSError *error, const char *fileName, unsigned line);
#define OBChainedError(error) _OBChainedError(error, __FILE__, __LINE__)
    
#define OBUserCancelledError(outError) _OBError(outError, NSCocoaErrorDomain, NSUserCancelledError, __FILE__, __LINE__, nil)
    
// Unlike the other routines in this file, but like all the other Foundation routines, this takes its key-value pairs with each value followed by its key.  The disadvantage to this is that you can't easily have runtime-ignored values (the nil value is a terminator rather than being skipped).
extern NSError *_OBErrorWithErrnoObjectsAndKeys(int errno_value, const char *function, NSString *argument, NSString *localizedDescription, ...) NS_REQUIRES_NIL_TERMINATION;
#define OBErrorWithErrnoObjectsAndKeys(outError, errno_value, function, argument, localizedDescription, ...) do { \
    OB_AUTORELEASING NSError **_outError = (outError); \
    OBASSERT(!_outError || !*_outError); /*no underlying error support*/ \
    if (_outError) \
        *_outError = _OBErrorWithErrnoObjectsAndKeys(errno_value, function, argument, localizedDescription, ## __VA_ARGS__); \
} while(0)
    
#define OBErrorWithErrno(error, errno_value, function, argument, localizedDescription) OBErrorWithErrnoObjectsAndKeys(error, errno_value, function, argument, localizedDescription, nil)
    
#if defined(__cplusplus)
} // extern "C"
#endif
