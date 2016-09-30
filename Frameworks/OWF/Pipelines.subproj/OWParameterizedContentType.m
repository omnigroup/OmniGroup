// Copyright 2000-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OWF/OWParameterizedContentType.h>

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

#import <OWF/OWContentType.h>
#import <OWF/OWHeaderDictionary.h>

RCS_ID("$Id$")

@implementation OWParameterizedContentType

+ (OWParameterizedContentType *)contentTypeForString:(NSString *)aString
{
    NSString *strippedString = [aString stringByRemovingSurroundingWhitespace];
    if ([NSString isEmptyString:strippedString])
        return nil;

    OFMultiValueDictionary *contentParameters;
    NSString *bareType;
    if ([strippedString containsString:@";"]) {
        contentParameters = [[OFMultiValueDictionary alloc] init];
        bareType = [OWHeaderDictionary parseParameterizedHeader:strippedString intoDictionary:contentParameters valueChars:nil];
    } else {
        contentParameters = nil;
        bareType = strippedString;
    }
    
    return [[OWParameterizedContentType alloc] initWithContentType:[OWContentType contentTypeForString:bareType] parameters:contentParameters];
}

- initWithContentType:(OWContentType *)aType;
{
    return [self initWithContentType:aType parameters:nil];
}

- initWithContentType:(OWContentType *)aType parameters:(OFMultiValueDictionary *)someParameters;
{
    if (!(self = [super init]))
        return nil;
    
    contentType = aType;
    _parameterLock = [[NSLock alloc] init];
    _parameters = someParameters;
    
    return self;
}

// API

- (OWContentType *)contentType;
{
    return contentType;
}

- (OFMultiValueDictionary *)parameters
{
    OFMultiValueDictionary *result;
    
    [_parameterLock lock];
    result = [_parameters mutableCopy];
    [_parameterLock unlock];
    return result;
}

- (NSString *)objectForKey:(NSString *)aName;
{
    NSString *object;

    [_parameterLock lock];
    object = [_parameters lastObjectForKey:aName];
    [_parameterLock unlock];
    return object;
}

- (void)setObject:(NSString *)newValue forKey:(NSString *)aName;
{
    [_parameterLock lock];
    if (_parameters == nil)
        _parameters = [[OFMultiValueDictionary alloc] init];
    [_parameters addObject:newValue forKey:aName];
    [_parameterLock unlock];
}

- (NSString *)contentTypeString;
{
    NSString *contentTypeString;

    contentTypeString = [contentType contentTypeString];
    [_parameterLock lock];
    if (_parameters != nil) {
        NSString *parameterString;
        
        parameterString = [OWHeaderDictionary formatHeaderParameters:_parameters onlyLastValue:YES];
        if ([parameterString length] > 0)
            contentTypeString = [NSString stringWithStrings:contentTypeString, @"; ", parameterString, nil];
    }
    [_parameterLock unlock];
    return contentTypeString;
}

- mutableCopyWithZone:(NSZone *)newZone
{
    OFMultiValueDictionary *copiedParameters;
    
    [_parameterLock lock];
    copiedParameters = [_parameters mutableCopyWithZone:newZone];
    [_parameterLock unlock];
    return [[[self class] allocWithZone:newZone] initWithContentType:contentType parameters:copiedParameters];
}

// OBObject subclass

- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *debugDictionary;

    debugDictionary = [super debugDictionary];
    [debugDictionary setObject:[contentType contentTypeString] forKey:@"contentType"];
    if (_parameters != nil)
        [debugDictionary setObject:_parameters forKey:@"parameters"];
    return debugDictionary;
}

@end
