// Copyright 2005-2009 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSError.h>

// This header was split out; import for backwards compatibility
#import <OmniBase/NSError-OBUtilities.h>

@interface NSError (OBExtensions)

- (NSError *)underlyingErrorWithDomain:(NSString *)domain;
- (NSError *)underlyingErrorWithDomain:(NSString *)domain code:(NSInteger)code;
- (BOOL)hasUnderlyingErrorDomain:(NSString *)domain code:(NSInteger)code;

- (BOOL)causedByUserCancelling;

- initWithPropertyList:(NSDictionary *)propertyList;
- (NSDictionary *)toPropertyList;
@end


