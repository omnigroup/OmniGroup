// Copyright 1997-2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFSimpleStringFormatter.h>

#import <Foundation/NSCoder.h>

RCS_ID("$Id$")

@implementation OFSimpleStringFormatter

+ (void)initialize;
{
    OBINITIALIZE;
    [self setVersion:0];
}

- init;
{
    return [self initWithMaxLength:0];
}

- initWithMaxLength:(unsigned int)value;
{
    if (!(self = [super init]))
        return nil;

    maxLength = value;
    return self;
}

- (void)setMaxLength:(unsigned int)value; { maxLength = value; }
- (unsigned int)maxLength; { return maxLength; }

- (NSString *)stringForObjectValue:anObject;
{
    if (![anObject isKindOfClass:[NSString class]])
        return nil;

    return anObject;
}

- (BOOL)isPartialStringValid:(NSString *)partialString newEditingString:(NSString **)newString errorDescription:(NSString **)error;
{
    if (maxLength == 0)
        return YES;

    return ([partialString length] <= maxLength);
}

- (BOOL)getObjectValue:(out id *)obj forString:(NSString *)string errorDescription:(out NSString **)error;
{
    if (maxLength != 0 && [string length] > maxLength)
        return NO;
    if (obj)
        *obj = string;
    return YES;
}

- (NSString *)inspectorClassName;
{
    return @"OASimpleStringFormatterInspector";
}

- (void)encodeWithCoder:(NSCoder *)coder;
{
    [super encodeWithCoder:coder];
    OFEncodeValueFrom(coder, &maxLength);
}

- initWithCoder:(NSCoder *)coder;
{
    if (!(self = [super initWithCoder:coder]))
        return nil;
    
    NSInteger version = [coder versionForClassName:NSStringFromClass([self class])];
    switch (version) {
        case 0:
            OFDecodeValueInto(coder, &maxLength);
            break;

        default:
            OBASSERT(NO);
            break;
    }
    
    return self;
}

@end
