// Copyright 2001-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSException.h>

@interface NSException (OBExtensions)
+ (void)raise:(NSString *)name reason:(NSString *)reason;
+ (void)raise:(NSString *)exceptionName posixErrorNumber:(int)posixErrorNumber format:(NSString *)format, ...
    __attribute__((format(__NSString__, 3, 4)));
+ (NSException *)exceptionWithName:(NSString *)exceptionName posixErrorNumber:(int)posixErrorNumber format:(NSString *)format, ...
    __attribute__((format(__NSString__, 3, 4)));
- (int)posixErrorNumber;
@end

extern NSString * const OBExceptionPosixErrorNumberKey;
extern NSString * const OBExceptionCarbonErrorNumberKey;

