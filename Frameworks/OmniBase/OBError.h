// Copyright 1997-2005, 2007-2009 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#if defined(__cplusplus)
extern "C" {
#endif
    
extern NSString * const OBErrorDomain;
extern NSString * const OBFileNameAndNumberErrorKey;

enum {
    OBErrorChained = 1,  /* skip code zero since that is often defined to be 'no error' */
};
    
extern NSError *_OBWrapUnderlyingError(NSError *underlyingError, NSString *domain, int code, const char *fileName, unsigned int line, NSString *firstKey, ...) NS_REQUIRES_NIL_TERMINATION;
    
// Clang complains if we have a function that takes NSError ** without returning BOOL/pointer.
// Bail on a NULL outError. Some Foundation code on 10.4 would crash if you did this, but on 10.5, many methods are documented to allow it. So let's allow it also.
#define _OBError(outError, domain, code, fileName, line, firstKey, ...) do { \
    NSError **_outError = (outError); \
    if (_outError) \
    *_outError = _OBWrapUnderlyingError(*_outError, domain, code, fileName, line, firstKey, ## __VA_ARGS__); \
} while(0)
    
    // Stacks another error on the input that simple records the calling code.  This can help establish the chain of failure when a callsite just fails because something else failed, without the overhead of adding another error code for that specific site.
#define OBChainError(error) _OBError(error, OBErrorDomain, OBErrorChained, __FILE__, __LINE__, nil)
extern NSError *OBFirstUnchainedError(NSError *error);
    
#ifdef OMNI_BUNDLE_IDENTIFIER
    // It is expected that -DOMNI_BUNDLE_IDENTIFIER=@"com.foo.bar" will be set when building your code.  Build configurations make this easy since you can set it in the target's configuration and then have your Other C Flags have -DOMNI_BUNDLE_IDENTIFIER=@\"$(OMNI_BUNDLE_IDENTIFIER)\" and also use $(OMNI_BUNDLE_IDENTIFIER) in your Info.plist instead of duplicating it.
#define OBError(error, code, description) _OBError(error, OMNI_BUNDLE_IDENTIFIER, code, __FILE__, __LINE__, NSLocalizedDescriptionKey, description, nil)
#define OBErrorWithInfo(error, code, ...) _OBError(error, OMNI_BUNDLE_IDENTIFIER, code, __FILE__, __LINE__, ## __VA_ARGS__)
#endif
    
// Unlike the other routines in this file, but like all the other Foundation routines, this takes its key-value pairs with each value followed by its key.  The disadvantage to this is that you can't easily have runtime-ignored values (the nil value is a terminator rather than being skipped).
extern NSError *_OBErrorWithErrnoObjectsAndKeys(int errno_value, const char *function, NSString *argument, NSString *localizedDescription, ...) NS_REQUIRES_NIL_TERMINATION;
#define OBErrorWithErrnoObjectsAndKeys(outError, errno_value, function, argument, localizedDescription, ...) do { \
    NSError **_outError = (outError); \
    OBASSERT(!_outError || !*_outError); /*no underlying error support*/ \
    if (_outError) \
        *_outError = _OBErrorWithErrnoObjectsAndKeys(errno_value, function, argument, localizedDescription, ## __VA_ARGS__); \
} while(0)
    
#define OBErrorWithErrno(error, errno_value, function, argument, localizedDescription) OBErrorWithErrnoObjectsAndKeys(error, errno_value, function, argument, localizedDescription, nil)
    
#if defined(__cplusplus)
} // extern "C"
#endif

