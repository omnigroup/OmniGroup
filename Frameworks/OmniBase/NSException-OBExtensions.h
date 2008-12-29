// Copyright 2001-2005, 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniBase/NSException-OBExtensions.h 98221 2008-03-04 21:06:19Z kc $

#import <Foundation/NSException.h>

@interface NSException (OBExtensions)
+ (void)raise:(NSString *)exceptionName posixErrorNumber:(int)posixErrorNumber format:(NSString *)format, ...;
+ (NSException *)exceptionWithName:(NSString *)exceptionName posixErrorNumber:(int)posixErrorNumber format:(NSString *)format, ...;
- (int)posixErrorNumber;
@end

extern NSString * const OBExceptionPosixErrorNumberKey;
extern NSString * const OBExceptionCarbonErrorNumberKey;

