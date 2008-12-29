// Copyright 2003-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OWXPlistValue.h"

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/CFPropertyList-OFExtensions.h>
#import <OmniIndex/OXDatabase.h>

RCS_ID("$Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OWF/Cache.subproj/OWXPlistValue.m 68913 2005-10-03 19:36:19Z kc $");

@interface OWXPlistValue (Private)

- (NSComparisonResult)_compareDictionary:(NSDictionary *)value1 to:(id)other;
- (NSComparisonResult)_compareArray:(NSArray *)value1 to:(id)other;

@end

@implementation OWXPlistValue

/* We're in a bundle, so we use +didLoad */
+ (void)didLoad
{
    [self self]; // Triggers +initialize.
}

// Register in +initialize, which gives other classes a way to force us to register, in case their +didLoad is called before ours.
+ (void)initialize
{
    OBINITIALIZE;
    
    [OXDatabase registerValueType:[[self alloc] init]];
}

- init
{
    [super init];

    writeFormat = kCFPropertyListBinaryFormat_v1_0;
    recentValue = nil;
    recentData = NULL;

    return self;
}

- (void)dealloc
{
    [recentValue release];
    if (recentData)
        CFRelease(recentData);
    [super dealloc];
}

- (NSString *)typeName;
{
    return @"plist";
}

- (NSString *)valueClassName;
{
    return @"NSObject";
}

- (NSComparisonResult)compare:(NSObject *)value1 to:(NSObject *)value2;
{
    OXNull *oxNull = [OXNull null];
    
    if (value1 == oxNull) {
        if (value2 == oxNull)
            return NSOrderedSame;
        return NSOrderedAscending;
    } else if (value2 == oxNull)
        return NSOrderedDescending;
    else if (value1 == value2)
        return NSOrderedSame;
    else if ([value1 isKindOfClass:[NSDictionary class]])
        return [self _compareDictionary:(NSDictionary *)value1 to:value2];
    else if ([value1 isKindOfClass:[NSArray class]])
        return [self _compareArray:(NSArray *)value1 to:value2];
    else
        return [(NSString *)value1 compare:(id)value2];
}

- (BOOL)isValue:(NSObject *)value1 equalToValue:(NSObject *)value2;
{
    OXNull *oxNull;
    
    if (value1 == value2)
        return YES;

    oxNull = [OXNull null];
    if (value1 == oxNull || value2 == oxNull)
        return NO;
    
    return [value1 isEqual:value2];
}

- (BOOL)isValue:(NSObject *)value1 notEqualToValue:(NSObject *)value2;
{
    return ![self isValue:value1 equalToValue:value2];
}

- (NSObject *)valueWithBytes:(void *)bytes length:(unsigned int)length;
{
    CFDataRef cfBuffer;
    CFPropertyListRef parsedPlist;
    CFStringRef errorString;

    if (length == 0) {
        if (allowsNull)
            return [OXNull null];
    }

    cfBuffer = CFDataCreateWithBytesNoCopy(kCFAllocatorDefault, bytes, length, kCFAllocatorNull);
    errorString = NULL;
    parsedPlist = CFPropertyListCreateFromXMLData(kCFAllocatorDefault, cfBuffer, kCFPropertyListImmutable, &errorString);
    CFRelease(cfBuffer);

    if (errorString != NULL) {
        NSException *parseError;
        
        OBASSERT(parsedPlist == NULL);

        parseError = [NSException exceptionWithName:NSInternalInconsistencyException reason:[NSString stringWithFormat:@"Cannot read stored plist: %@", errorString] userInfo:nil];
        CFRelease(errorString);
        [parseError raise];
    }

    OBASSERT(parsedPlist != NULL);
    return (NSObject *)parsedPlist;  // The caller expects to have to release the returned object
}

- (unsigned int)byteSizeOfValue:(NSObject *)value;
{
    CFDataRef serialized;
    
    if (value == [OXNull null])
        return 0;
    
    if (value == recentValue && recentData != NULL)
        return CFDataGetLength(recentData);

    serialized = OFCreateDataFromPropertyList(kCFAllocatorDefault, value, writeFormat);
    OBASSERT(serialized != NULL);  // OFCreateDataFromPropertyList() will raise if it encounters an error
    
    if (recentValue)
        [recentValue release];
    if (recentData)
        CFRelease(recentData);
    recentValue = [value retain];
    recentData = serialized;  // transfer retain count to ivar
    
    return CFDataGetLength(serialized);
}

- (void)writeValue:(NSObject *)value toBuffer:(void *)buffer;
{
    if (value == [OXNull null])
        return;
        
    if (value == recentValue && recentData != NULL) {
        CFRange fullBuffer;

        fullBuffer.location = 0;
        fullBuffer.length = CFDataGetLength(recentData);
        CFDataGetBytes(recentData, fullBuffer, buffer);
        [recentValue release];
        recentValue = nil;
        CFRelease(recentData);
        recentData = NULL;
        return;
    }

    if (recentValue) {
        [recentValue release];
        recentValue = nil;
    }
    if (recentData) {
        CFRelease(recentData);
        recentData = NULL;
    }
    
    {
        CFDataRef serialized;
        CFRange fullBuffer;

        // UNDONE / TODO: We could do this more efficiently by using CFWriteStreamCreateWithBuffer/CFPropertyListWriteToStream, but we would need to know the length of the buffer beforehand.

        serialized = OFCreateDataFromPropertyList(kCFAllocatorDefault, value, writeFormat);
        fullBuffer.location = 0;
        fullBuffer.length = CFDataGetLength(serialized);
        CFDataGetBytes(serialized, fullBuffer, buffer);
        CFRelease(serialized);
    }
}

- (BOOL)isFixedLength;
{
    return NO;
}

- (BOOL)requiresWidth;
{
    return NO;
}

#if 0
- (NSObject *)valueFromScanner:(NSScanner *)scanner;
{
    ...
}
#endif

- (NSString *)stringValue:(NSObject *)value;
{
    return [value description];
}

/* Can't create indexes on plist columns as yet ... */
- (OXCompareFunction)comparisonFunction;
{
    return NULL;
}

@end

@implementation OWXPlistValue (Private)

- (NSComparisonResult)_compareDictionary:(NSDictionary *)value1 to:(id)other
{
    NSDictionary *value2;
    NSArray *keys1, *keys2;
    NSComparisonResult order;
    unsigned int keyIndex, keyCount;
    
    if (![other isKindOfClass:[NSDictionary class]])
        return NSOrderedDescending;

    value2 = other;
    keys1 = [[value1 allKeys] sortedArrayUsingSelector:@selector(compare:)];
    keys2 = [[value2 allKeys] sortedArrayUsingSelector:@selector(compare:)];

    order = [self _compareArray:keys1 to:keys2];
    if (order != NSOrderedSame)
        return order;

    keyCount = [keys1 count];
    for(keyIndex = 0; keyIndex < keyCount; keyIndex ++) {
        NSString *key = [keys1 objectAtIndex:keyIndex];

        order = [self compare:[value1 objectForKey:key] to:[value2 objectForKey:key]];
        if (order != NSOrderedSame)
            return order;
    }

    return NSOrderedSame;
}

- (NSComparisonResult)_compareArray:(NSArray *)value1 to:(id)other;
{
    NSArray *value2;
    unsigned int count1, count2, index;
    NSComparisonResult order;
    
    if ([other isKindOfClass:[NSDictionary class]])
        return NSOrderedAscending;
    else if (![other isKindOfClass:[NSArray class]])
        return NSOrderedDescending;

    value2 = other;
    count1 = [value1 count];
    count2 = [value2 count];
    index = 0;
    for(;;) {
        if (index == count1)
            if (index == count2)
                return NSOrderedSame;
            else
                return NSOrderedAscending;
        else
            if (index == count2)
                return NSOrderedDescending;

        order = [self compare:[value1 objectAtIndex:index] to:[value2 objectAtIndex:index]];
        if (order != NSOrderedSame)
            return order;

        index ++;
    }
}

@end
