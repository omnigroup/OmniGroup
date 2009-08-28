// Copyright 2005-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSError.h>
#import <OmniBase/OBError.h>

#if defined(__cplusplus)
extern "C" {
#endif

extern NSString * const OBUserCancelledActionErrorKey;

@interface NSError (OBExtensions)

- (BOOL)hasUnderlyingErrorDomain:(NSString *)domain code:(int)code;
- (BOOL)causedByUserCancelling;

- initWithPropertyList:(NSDictionary *)propertyList;
- (NSDictionary *)toPropertyList;
@end

#if defined(__cplusplus)
} // extern "C"
#endif

