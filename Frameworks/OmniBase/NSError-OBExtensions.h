// Copyright 2005-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniBase/NSError-OBExtensions.h 102857 2008-07-15 04:22:17Z bungi $

#import <Foundation/NSError.h>

#if defined(__cplusplus)
extern "C" {
#endif
    
extern NSString * const OBUserCancelledActionErrorKey;
extern NSString * const OBFileNameAndNumberErrorKey;

@interface NSError (OBExtensions)

- (BOOL)hasUnderlyingErrorDomain:(NSString *)domain code:(int)code;
- (BOOL)causedByUserCancelling;

- initWithPropertyList:(NSDictionary *)propertyList;
- (NSDictionary *)toPropertyList;
@end

extern void OBErrorv(NSError **error, NSString *domain, int code, const char *fileName, unsigned int line, NSString *firstKey, va_list args);
extern void _OBError(NSError **error, NSString *domain, int code, const char *fileName, unsigned int line, NSString *firstKey, ...);

#ifdef OMNI_BUNDLE_IDENTIFIER
// It is expected that -DOMNI_BUNDLE_IDENTIFIER=@"com.foo.bar" will be set when building your code.  Build configurations make this easy since you can set it in the target's configuration and then have your Other C Flags have -DOMNI_BUNDLE_IDENTIFIER=@\"$(OMNI_BUNDLE_IDENTIFIER)\" and also use $(OMNI_BUNDLE_IDENTIFIER) in your Info.plist instead of duplicating it.
#define OBError(error, code, description) _OBError(error, OMNI_BUNDLE_IDENTIFIER, code, __FILE__, __LINE__, NSLocalizedDescriptionKey, description, nil)
#define OBErrorWithInfo(error, code, ...) _OBError(error, OMNI_BUNDLE_IDENTIFIER, code, __FILE__, __LINE__, ## __VA_ARGS__)
#endif

// Unlike the other routines in this file, but like all the other Foundation routines, this takes its key-value pairs with each value followed by its key.  The disadvantage to this is that you can't easily have runtime-ignored values (the nil value is a terminator rather than being skipped).
void OBErrorWithErrnoObjectsAndKeys(NSError **error, int errno_value, const char *function, NSString *argument, NSString *localizedDescription, ...);
#define OBErrorWithErrno(error, errno_value, function, argument, localizedDescription) OBErrorWithErrnoObjectsAndKeys(error, errno_value, function, argument, localizedDescription, nil)


#if defined(__cplusplus)
} // extern "C"
#endif

