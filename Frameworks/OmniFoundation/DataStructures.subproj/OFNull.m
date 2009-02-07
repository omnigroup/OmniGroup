// Copyright 1997-2005, 2007-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFNull.h>

RCS_ID("$Id$")

@interface OFNullString : NSString
@end

@implementation OFNull

NSString *OFNullStringObject;
static OFNull *nullObject;

+ (void) initialize;
{
    OBINITIALIZE;

    nullObject = [[OFNull alloc] init];
    OFNullStringObject = [[OFNullString alloc] init];
}

+ (id)nullObject;
{
    return nullObject;
}

+ (NSString *)nullStringObject;
{
    return OFNullStringObject;
}

- (BOOL)isNull;
{
    return YES;
}

- (float)floatValue;
{
    return 0.0f;
}

- (int)intValue;
{
    return 0;
}

- (NSString *)descriptionWithLocale:(NSDictionary *)locale
                             indent:(unsigned)level
{
    return @"*null*";
}

- (NSString *)description;
{
    return @"*null*";
}

- (NSString *)shortDescription;
{
    return [self description];
}

@end

@implementation NSObject (Null)

- (BOOL)isNull;
{
    return NO;
}

@end

#import <Foundation/NSNull.h>
@implementation NSNull (OFNull)
- (BOOL) isNull
{
    return YES;
}
@end

@implementation OFNullString

- (NSUInteger)length;
{
    return 0;
}

- (unichar)characterAtIndex:(NSUInteger)anIndex;
{
    [NSException raise:NSRangeException format:@""];
    return '\0';
}

- (BOOL)isNull;
{
    return YES;
}

- (NSString *)description;
{
    return @"*null*";
}

- (NSString *)shortDescription;
{
    return [self description];
}

@end

#if !TARGET_OS_IPHONE

#import <objc/Object.h>

@interface Object (Null)
- (BOOL)isNull;
@end

@implementation Object (Null)

- (BOOL)isNull;
{
    return NO;
}

@end
#endif

