// Copyright 2001-2005, 2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniBase/NSException-OBExtensions.h>

#import <OmniBase/macros.h>
#import <OmniBase/OBUtilities.h>
#import <OmniBase/rcsid.h>

RCS_ID("$Id$");

@implementation NSException (OBExtensions)

+ (void)raise:(NSString *)exceptionName posixErrorNumber:(int)posixErrorNumber format:(NSString *)format, ...;
{
    va_list argList;
    va_start(argList, format);
    NSString *formattedString = [[[NSString alloc] initWithFormat:format arguments:argList] autorelease];
    va_end(argList);
    [[NSException exceptionWithName:exceptionName reason:formattedString userInfo:[NSDictionary dictionaryWithObject:[NSNumber numberWithInt:posixErrorNumber] forKey:OBExceptionPosixErrorNumberKey]] raise];
}

+ (NSException *)exceptionWithName:(NSString *)exceptionName posixErrorNumber:(int)posixErrorNumber format:(NSString *)format, ...;
{
    va_list argList;
    va_start(argList, format);
    NSString *formattedString = [[[NSString alloc] initWithFormat:format arguments:argList] autorelease];
    va_end(argList);
    return [NSException exceptionWithName:exceptionName reason:formattedString userInfo:[NSDictionary dictionaryWithObject:[NSNumber numberWithInt:posixErrorNumber] forKey:OBExceptionPosixErrorNumberKey]];
}

- (int)posixErrorNumber;
{
    NSNumber *errorNumber = [[self userInfo] objectForKey:OBExceptionPosixErrorNumberKey];
    return errorNumber != nil ? [errorNumber intValue] : 0;
}

@end

NSString * const OBExceptionPosixErrorNumberKey = @"errno";
NSString * const OBExceptionCarbonErrorNumberKey = @"OSErr";
