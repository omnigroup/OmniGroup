// Copyright 2005, 2007-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFUnit.h>
#import <OmniFoundation/OFUnits-Private.h>

#import <OmniFoundation/NSDictionary-OFExtensions.h>
#import <OmniFoundation/NSMutableDictionary-OFExtensions.h>
#import <OmniFoundation/OFDimensionedValue.h>
#import <OmniFoundation/OFRationalNumber.h>
#import <OmniFoundation/OFUnits.h>

RCS_ID("$Id$");

@interface OFUnit (Private)

@end

@implementation OFUnit

- init
{
    self = [super init];
    if (self) {
        ascrUnit = kUnknownType;
    }
    return self;
}

- (void)dealloc
{
    [name release];
    [abbreviation release];
    [selectionName release];
    [displayFormat release];
    [scanSuffixes release];
    [smallerUnit release];
    [postfixUnit release];
    [definition release];
    [super dealloc];
}

- (BOOL)readFromPropertyList:(NSDictionary *)plist container:(OFUnits *)units;
{
    BOOL ok;
    
    // NOTE: The name and unit keys are also understood by OFUnits.
    
    if (!abbreviation)
        abbreviation = [[plist objectForKey:unitKeyAbbreviation] retain];
    if (!name)
        name = [[plist objectForKey:unitKeyName] retain];
    if (!name && abbreviation)
        name = [abbreviation retain];
    
    if (!name || !abbreviation)
        return NO;
    
    ok = YES;
    
    if (!selectionName)
        selectionName = [[plist objectForKey:unitKeySelectionTitle] retain];
    if (!selectionName && abbreviation)
        selectionName = [abbreviation retain];
    if (!displayFormat)
        displayFormat = [[plist objectForKey:unitKeyDisplayFormat] retain];
    if (!displayFormat && abbreviation)
        displayFormat = [[@"%@ " stringByAppendingString:abbreviation] retain];
    
    if (units != nil) {
        OBASSERT(smallerUnit == nil);
        OBASSERT(definition == nil);
        
        NSString *smaller = [plist objectForKey:unitKeySmallerUnit];
        if (smaller) {
            smallerUnit = [units unitByName:smaller];
            if (!smallerUnit)
                NSLog(@"Unknown unit %@ referred to by %@", smaller, name);
            [smallerUnit retain];
        }
        //    NSArray *steps = [plist objectForKey:unitKeyRulerSteps];
        
        NSString *base = [plist objectForKey:unitKeyDefinition];
        if (base) {
            OFDimensionedValue *dim = [units parseString:base defaultUnit:nil];
            if (!dim || ![dim dimension]) {
                NSLog(@"Unit %@ has unparsable definition \"%@\"", name, base);
                ok = NO;
            }
            definition = [dim retain];
        }
    }
    
    id aliases = [plist objectForKey:unitKeyAlternateNames];
    if (aliases) {
        NSEnumerator *aliasEnumerator = [aliases objectEnumerator];
        NSMutableSet *scannables = scanSuffixes? [scanSuffixes mutableCopy] : [[NSMutableSet alloc] init];
        NSString *scannable;
        while( (scannable = [aliasEnumerator nextObject]) )
            [scannables addObject:scannable];
        [scanSuffixes autorelease];
        scanSuffixes = [scannables copy];
        [scannables release];
    }
    
    isGroupBase = [plist boolForKey:unitKeyIsGroupBase defaultValue:NO];
    
    id ascrValue = [plist objectForKey:unitKeyAppleEventType];
    if (ascrValue) {
        if (!OFGet4CCFromPlist(ascrValue, (uint32_t *)&ascrUnit))
            ok = NO;
    }
        
    return ok;
}

- (NSMutableDictionary *)propertyListRepresentationInContainer:(OFUnits *)units base:(OFUnit *)baseDefinition;
{
    NSMutableDictionary *plist = [NSMutableDictionary dictionary];
    
    if (baseDefinition != nil) {
        OBASSERT([[self name] isEqualToString:[baseDefinition name]]);
        OBASSERT([abbreviation isEqualToString:baseDefinition->abbreviation]);
    }
    
    NSString *defaultDisplayFormat = [@"%@ " stringByAppendingString:abbreviation];
    if (baseDefinition)
        defaultDisplayFormat = [baseDefinition displayFormat];
    [plist setObject:displayFormat forKey:unitKeyDisplayFormat defaultObject:defaultDisplayFormat];
    
    [plist setObject:selectionName forKey:unitKeySelectionTitle defaultObject:[baseDefinition selectionName]];
    
    if (smallerUnit) {
        NSString *defaultSmallerUnit = baseDefinition? [units nameOfUnit:(baseDefinition->smallerUnit)] : nil;
        [plist setObject:[units nameOfUnit:smallerUnit] forKey:unitKeySmallerUnit defaultObject:defaultSmallerUnit];
    }
    
    [plist setObject:[units storageStringForValue:definition] forKey:unitKeyDefinition defaultObject:[units storageStringForValue:[baseDefinition definition]]];

    if (scanSuffixes && [scanSuffixes count] && !(baseDefinition && [scanSuffixes isEqual:(baseDefinition->scanSuffixes)])) {
        // TODO: Differencing from base definition.
        [plist setObject:[scanSuffixes allObjects] forKey:unitKeyAlternateNames];
    }
    
    [plist setBoolValue:isGroupBase forKey:unitKeyIsGroupBase defaultValue:( baseDefinition? baseDefinition->isGroupBase : NO)];
    
    if ((baseDefinition && ascrUnit != [baseDefinition typeCodeValue]) ||
        (!baseDefinition && ascrUnit != kUnknownType && ascrUnit != 0)) {
        id r = OFCreatePlistFor4CC(ascrUnit);
        [plist setObject:r forKey:unitKeyAppleEventType];
        [r release];
    }
    
    if (baseDefinition != nil && [plist count] == 0)
        return nil;
    
    [plist setObject:abbreviation forKey:unitKeyAbbreviation];
    if (![abbreviation isEqualToString:name])
        [plist setObject:name forKey:unitKeyName];
    
    return plist;
}

- (OFUnit *)postfixUnit;
{
    return postfixUnit;
}

- (NSString *)name
{
    return name;
}

- (NSString *)abbreviation
{
    return abbreviation;
}

- (BOOL)hasName:(NSString *)anyName;
{
    
    BOOL suff = ([scanSuffixes member:anyName] != nil);
    BOOL abbr = [abbreviation isEqualToString:anyName];

    NSLog(@"<OFUnit %@> %s%@ [%d %d]", name, _cmd, anyName, suff, abbr);
    
    return suff || abbr;
}

- (OFDimensionedValue *)definition
{
    /* TODO: Should this maybe live in OFUnits ? */
    return definition;
}

- (NSString *)selectionName;  // A name which could be put on e.g. a units popup (localized)
{
    return selectionName;
}

- (NSString *)displayFormat;  // TODO: Separate into strings for editing, for storage, for display (attributed string?)
{
    return displayFormat;
}

- (FourCharCode)typeCodeValue;
{
    return ascrUnit;
}

@end

@implementation OFUnit (DelegatesAndDataSources)

@end

@implementation OFUnit (Private)

@end
