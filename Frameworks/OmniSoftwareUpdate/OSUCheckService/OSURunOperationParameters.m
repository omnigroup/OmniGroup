// Copyright 2001-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OSURunOperationParameters.h"

#import <objc/runtime.h>

RCS_ID("$Id$");

OB_REQUIRE_ARC // Since we don't have a -dealloc method

@implementation OSURunOperationParameters

#pragma mark - NSSecureCoding

// Needed for passing over a XPC connection
+ (BOOL)supportsSecureCoding;
{
    return YES;
}

#pragma mark - NSCoding

- (void)encodeWithCoder:(NSCoder *)aCoder;
{
#define ENC_OBJECT(x) [aCoder encodeObject:_ ## x forKey:@"" #x]
#define ENC_BOOL(x) [aCoder encodeBool:_ ## x forKey:@"" #x]
    
    ENC_OBJECT(firstHopHost);
    ENC_OBJECT(baseURLString);
    ENC_OBJECT(appIdentifier);
    ENC_OBJECT(appVersionString);
    ENC_OBJECT(track);
    
    ENC_BOOL(includeHardwareInfo);
    ENC_BOOL(reportMode);
    
    ENC_OBJECT(uuidString);
    ENC_OBJECT(licenseType);
    ENC_OBJECT(osuVersionString);
}

- (id)initWithCoder:(NSCoder *)aDecoder; // NS_DESIGNATED_INITIALIZER
{
    if (!(self = [super init]))
        return nil;
    
#define DEC_OBJECT(cls, x) _ ## x = [(typeof(_ ## x))[aDecoder decodeObjectOfClass:[cls class] forKey:@"" #x] copy]
#define DEC_BOOL(x) _ ## x = [aDecoder decodeBoolForKey:@"" #x]
    
    DEC_OBJECT(NSString, firstHopHost);
    DEC_OBJECT(NSString, baseURLString);
    DEC_OBJECT(NSString, appIdentifier);
    DEC_OBJECT(NSString, appVersionString);
    DEC_OBJECT(NSString, track);
    
    DEC_BOOL(includeHardwareInfo);
    DEC_BOOL(reportMode);
    
    DEC_OBJECT(NSString, uuidString);
    DEC_OBJECT(NSString, licenseType);
    DEC_OBJECT(NSString, osuVersionString);
    
    return self;
}

#pragma mark - Debugging

#if defined(DEBUG)
- (NSString *)debugDescription;
{
    // Enumerate properties we declare in this class and just dump a dictionary of their names & values
    // This approach automatically picks up new properties added in the header, but depends on nobody subclassing this class
    Class cls = [OSURunOperationParameters class];
    OBASSERT([self class] == cls, @"Calling -debugDescription on a subclass of %@ will produce incomplete results!", NSStringFromClass(cls));
    
    unsigned int propertyCount = 0;
    objc_property_t *propertyList = class_copyPropertyList(cls, &propertyCount);
    if (propertyList == NULL) {
        return [super debugDescription];
    }
    
    NSMutableDictionary *propertyValues = [NSMutableDictionary dictionary];
    for (unsigned int propertyIdx = 0; propertyIdx < propertyCount; propertyIdx++) {
        const char *propertyName = property_getName(propertyList[propertyIdx]);
        NSString *key = [NSString stringWithCString:propertyName encoding:NSUTF8StringEncoding];
        propertyValues[key] = [self valueForKey:key];
    }
    free(propertyList);
    propertyList = NULL;
    
    return [NSString stringWithFormat:@"<%@:%p %@>", NSStringFromClass([self class]), self, propertyValues];
}
#endif

@end
