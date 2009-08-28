// Copyright 2004-2005, 2007-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFVersionNumber.h>

#import <OmniFoundation/OFStringScanner.h>

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
#import <UIKit/UIDevice.h>
#else
#import <CoreServices/CoreServices.h>
#endif

RCS_ID("$Id$");

@implementation OFVersionNumber

+ (OFVersionNumber *)userVisibleOperatingSystemVersionNumber;
{
    static OFVersionNumber *userVisibleOperatingSystemVersionNumber = nil;
    if (userVisibleOperatingSystemVersionNumber)
        return userVisibleOperatingSystemVersionNumber;
    
#if TARGET_OS_IPHONE
    UIDevice *device = [UIDevice currentDevice];
    NSString *versionString = device.systemVersion;
#else 
    // sysctlbyname("kern.osrevision"...) returns an error, Radar #3624904
    //setSysctlStringKey(info, "kern.osrevision");

    SInt32 major, minor, bug;
    Gestalt(gestaltSystemVersionMajor, &major);
    Gestalt(gestaltSystemVersionMinor, &minor);
    Gestalt(gestaltSystemVersionBugFix, &bug);
    
    NSString *versionString = [NSMakeCollectable(CFStringCreateWithFormat(kCFAllocatorDefault, NULL, CFSTR("%d.%d.%d"), major, minor, bug)) autorelease];
#endif

    // TODO: Add a -initWithComponents:count:?
    userVisibleOperatingSystemVersionNumber = [[self alloc] initWithVersionString:versionString];

    return userVisibleOperatingSystemVersionNumber;
}

// Meant to be called during initialization, not repeatedly, since this allocates and discards an instance.
+ (BOOL)isOperatingSystemLaterThanVersionString:(NSString *)versionString;
{
    OFVersionNumber *version = [[OFVersionNumber alloc] initWithVersionString:versionString];
    BOOL isLater = ([[OFVersionNumber userVisibleOperatingSystemVersionNumber] compareToVersionNumber:version] != NSOrderedAscending);
    [version release];
    return isLater;
}

/* Initializes the receiver from a string representation of a version number.  The input string may have an optional leading 'v' or 'V' followed by a sequence of positive integers separated by '.'s.  Any trailing component of the input string that doesn't match this pattern is ignored.  If no portion of this string matches the pattern, nil is returned. */
- initWithVersionString:(NSString *)versionString;
{
    OBPRECONDITION([versionString isKindOfClass:[NSString class]]);
    
    // Input might be from a NSBundle info dictionary that could be misconfigured, so check at runtime too
    if (!versionString || ![versionString isKindOfClass:[NSString class]]) {
        [self release];
        return nil;
    }

    _originalVersionString = [versionString copy];
    
    NSMutableString *cleanVersionString = [[NSMutableString alloc] init];
    OFStringScanner *scanner = [[OFStringScanner alloc] initWithString:versionString];
    unichar c = scannerPeekCharacter(scanner);
    if (c == 'v' || c == 'V')
        scannerSkipPeekedCharacter(scanner);

    while (scannerHasData(scanner)) {
        // TODO: Add a OFCharacterScanner method that allows you specify the maximum uint32 value (and a parameterless version that uses UINT_MAX) and passes back a BOOL indicating success (since any uint32 would be valid).
        NSUInteger location = scannerScanLocation(scanner);
        unsigned int component = [scanner scanUnsignedIntegerMaximumDigits:10];

        if (location == scannerScanLocation(scanner))
            // Failed to scan integer
            break;

        [cleanVersionString appendFormat: _componentCount ? @".%u" : @"%u", component];

        _componentCount++;
        _components = realloc(_components, sizeof(*_components) * _componentCount);
        _components[_componentCount - 1] = component;

        c = scannerPeekCharacter(scanner);
        if (c != '.')
            break;
        scannerSkipPeekedCharacter(scanner);
    }

    if ([cleanVersionString isEqualToString:_originalVersionString])
        _cleanVersionString = [_originalVersionString retain];
    else
        _cleanVersionString = [cleanVersionString copy];
    
    [cleanVersionString release];
    [scanner release];

    if (_componentCount == 0) {
        // Failed to parse anything and we don't allow empty version strings.  For now, we'll not assert on this, since people might want to use this to detect if a string begins with a valid version number.
        [self release];
        return nil;
    }
    
    return self;
}

- (void)dealloc;
{
    [_originalVersionString release];
    [_cleanVersionString release];
    if (_components)
        free(_components);
    [super dealloc];
}


#pragma mark -
#pragma mark API

- (NSString *)originalVersionString;
{
    return _originalVersionString;
}

- (NSString *)cleanVersionString;
{
    return _cleanVersionString;
}

- (unsigned int)componentCount;
{
    return _componentCount;
}

- (unsigned int)componentAtIndex:(unsigned int)componentIndex;
{
    // This treats the version as a infinite sequence ending in "...0.0.0.0", making comparison easier
    if (componentIndex < _componentCount)
        return _components[componentIndex];
    return 0;
}

#pragma mark -
#pragma mark NSCopying

- (id)copyWithZone:(NSZone *)zone;
{
    return [self retain];
}

#pragma mark -
#pragma mark Comparison

- (NSUInteger)hash;
{
    return [_cleanVersionString hash];
}

- (BOOL)isEqual:(id)otherObject;
{
    if (![otherObject isKindOfClass:[OFVersionNumber class]])
        return NO;
    return [self compareToVersionNumber:(OFVersionNumber *)otherObject] == NSOrderedSame;
}

- (NSComparisonResult)compare:(id)otherObject;
{
    if (!otherObject || [otherObject isKindOfClass:[OFVersionNumber class]])
        return [self compareToVersionNumber:otherObject];
    
    if ([otherObject isKindOfClass:[NSString class]]) {
        OFVersionNumber *otherNumber = [[[OFVersionNumber alloc] initWithVersionString:otherObject] autorelease];
        return [self compareToVersionNumber:otherNumber];
    }
    
    // We could maybe make some attempt with NSNumber at some point, but the conversion from a floating point number a dotted sequence of integers is iffy.
    return NSOrderedAscending;
}

- (NSComparisonResult)compareToVersionNumber:(OFVersionNumber *)otherVersion;
{
    if (!otherVersion)
        return NSOrderedAscending;

    unsigned int componentIndex, componentCount = MAX(_componentCount, [otherVersion componentCount]);
    for (componentIndex = 0; componentIndex < componentCount; componentIndex++) {
        unsigned int component = [self componentAtIndex:componentIndex];
        unsigned int otherComponent = [otherVersion componentAtIndex:componentIndex];

        if (component < otherComponent)
            return NSOrderedAscending;
        else if (component > otherComponent)
            return NSOrderedDescending;
    }

    return NSOrderedSame;
}

#pragma mark -
#pragma mark Debugging

- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *dict = [super debugDictionary];

    [dict setObject:_originalVersionString forKey:@"originalVersionString"];
    [dict setObject:_cleanVersionString forKey:@"cleanVersionString"];

    NSMutableArray *components = [NSMutableArray array];
    unsigned int componentIndex;
    for (componentIndex = 0; componentIndex < _componentCount; componentIndex++)
        [components addObject:[NSNumber numberWithUnsignedInt:_components[componentIndex]]];
    [dict setObject:components forKey:@"components"];

    return dict;
}

@end
