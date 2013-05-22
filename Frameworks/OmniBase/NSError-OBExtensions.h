// Copyright 2005-2009, 2013 Omni Development, Inc. All rights reserved.
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
- (BOOL)causedByMissingFile;
- (BOOL)causedByUnreachableHost;

- initWithPropertyList:(NSDictionary *)propertyList;
- (NSDictionary *)toPropertyList;

// Useful for test cases that intentionally provoke errors that might be logged to the console as well as being reported to the user via other means (if UI was hooked up). Only suppresses the error for the duration of the given action, and only on the calling thread.
+ (void)suppressingLogsWithUnderlyingDomain:(NSString *)domain code:(NSInteger)code action:(void (^)(void))action;

// If the error isn't being suppressed, the format and arguments are turned into a string and logged, along with the property list version of the error.
- (void)log:(NSString *)format, ... NS_FORMAT_FUNCTION(1,2);
- (void)log:(NSString *)format arguments:(va_list)arguments;
- (void)logWithReason:(NSString *)reason;

@end
