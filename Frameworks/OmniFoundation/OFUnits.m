// Copyright 2005-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFUnits.h>
#import <OmniFoundation/OFUnits-Private.h>

#import <OmniFoundation/CFArray-OFExtensions.h>
#import <OmniFoundation/OFDimensionedValue.h>
#import <OmniFoundation/OFUnit.h>

RCS_ID("$Id$");

@interface OFUnits (Private)

@end

@implementation OFUnits

+ (OFUnits *)loadUnitsNamed:(NSString *)resourceName inBundle:(NSBundle *)aBundle;
{
    NSString *mainPath = [aBundle pathForResource:resourceName ofType:@"ofunits"];
    if (!mainPath)
        return nil;
    id definitions = [NSArray arrayWithContentsOfFile:mainPath];
    
    OFUnits *result = [[self alloc] init];
    [result readPropertyList:definitions];
    return [result autorelease];
}

- (void)readPropertyList:(NSArray *)ul
{
    unsigned unitCount, unitIndex;
    NSMutableArray *modifyingUnits, *newUnits;
    
    unitCount = [ul count];
    modifyingUnits = [[NSMutableArray alloc] initWithCapacity:unitCount];
    newUnits = [[NSMutableArray alloc] init];
    for(unitIndex = 0; unitIndex < unitCount; unitIndex ++) {
        NSDictionary *loadingInfo = [ul objectAtIndex:unitIndex];
        OFUnit *loadingUnit;
        NSString *identifier;
        
        loadingUnit = nil;
        if( (identifier = [loadingInfo objectForKey:unitKeyName]) || (identifier = [loadingInfo objectForKey:unitKeyAbbreviation]) ) {
            loadingUnit = [self unitByName:identifier];
        }
        if (!loadingUnit) {
            loadingUnit = [[OFUnit alloc] init];
            [newUnits addObject:loadingUnit];
            [loadingUnit release];
            [loadingUnit readFromPropertyList:loadingInfo container:nil];
        }
        [modifyingUnits addObject:loadingUnit];
    }
    
    if ([newUnits count]) {
        if (units)
            [newUnits addObjectsFromArray:units];
        [units autorelease];
        units = [[NSArray alloc] initWithArray:newUnits];
    }
    [newUnits release];
    newUnits = nil;
    
    OBASSERT([modifyingUnits count] == [ul count]);
    
    /* Run through a second time to get the cross-references */
    for(unitIndex = 0; unitIndex < unitCount; unitIndex ++) {
        [[modifyingUnits objectAtIndex:unitIndex] readFromPropertyList:[ul objectAtIndex:unitIndex] container:self];
    }
    
    [modifyingUnits release];
    
    /* TODO: Support localized unit names */
}

- (void)dealloc
{
    [units release];
    [super dealloc];
}

- propertyListRepresentation;
{
    return [self propertyListRepresentationWithBase:nil];
}

- propertyListRepresentationWithBase:(OFUnits *)base
{
    NSMutableArray *plist = [NSMutableArray array];
    unsigned unitCount, unitIndex;
    
    unitCount = [units count];
    for(unitIndex = 0; unitIndex < unitCount; unitIndex ++) {
        OFUnit *aUnit = [units objectAtIndex:unitIndex];
        OFUnit *baseDefinition = [base unitByName:[aUnit name]];
        id representation = [aUnit propertyListRepresentationInContainer:self base:baseDefinition];
        if (representation)
            [plist addObject:representation];
    }
    
    return plist;
}

- (NSArray *)units;
{
    return units;
}

- (NSString *)nameOfUnit:(OFUnit *)aUnit;
{
    return [aUnit name];
}

- (OFUnit *)unitByName:(NSString *)storageName;
{
    OFForEachInArray(units, OFUnit *, aUnit, {
        if ([storageName isEqualToString:[aUnit name]])
            return aUnit;
    });
    
    return nil;
}

- (OFUnit *)unitFromString:(NSString *)inputString;
{
    OFForEachInArray(units, OFUnit *, aUnit, {
        if ([aUnit hasName:inputString])
            return aUnit;
    });
    
    return nil;
}

- (NSString *)storageStringForValue:(OFDimensionedValue *)dim;
{
    if (dim == nil)
        return nil;
    
    /* TODO: This won't work for some odd cases. */
    OFUnit *dimension = [dim dimension];
    NSString *numericPart = [[dim value] stringValue];
    if (dimension)
        return [NSString stringWithFormat:[dimension displayFormat], numericPart];
    else
        return numericPart;
}

static inline id make2ple(id a, id b)
{
    const void *v[2];
    v[0] = a;
    v[1] = b;
    return (id)CFArrayCreate(kCFAllocatorDefault,v,2,&OFNSObjectArrayCallbacks);
}

- (NSNumber *)conformUnit:(OFUnit *)aUnit toUnit:(OFUnit *)anotherUnit;
{
    /* TODO: Cache these conformation paths. */
    
    if (!aUnit || !anotherUnit)
        return nil;
    
    NSMutableArray *pathA = [NSMutableArray array];
    OFUnit *walk, *commonUnit;
    
    walk = aUnit;
    for(;;) {
        [pathA addObject:walk];
        if (walk == anotherUnit)  // unnecc., but easy optimization
            break;
        OFDimensionedValue *b = [walk definition];
        if (!b)
            break;
        walk = [b dimension];
    }
    
    NSNumber *bFactors = nil;

    walk = anotherUnit;
    for(;;) {
        NSUInteger ix = [pathA indexOfObjectIdenticalTo:walk];
        if (ix != NSNotFound) {
            [pathA removeObjectsInRange:(NSRange){ix, [pathA count] - ix}];
            commonUnit = walk;
            break;
        }
        OFDimensionedValue *b = [walk definition];
        if (!b)
            return nil; // no path from aUnit to anotherUnit
        walk = [b dimension];
        if (bFactors)
            bFactors = [OFRationalNumber numberByPerformingOperation:OFArithmeticOperation_Multiply withNumber:bFactors andNumber:[b value]];
        else
            bFactors = [b value];
    }
    
    // Now bFactors is the conversion factor from anotherUnit to the common base unit.
    
    NSNumber *aFactors = [NSNumber numberWithInt:1];
    unsigned aSteps;
    for(aSteps = 0; aSteps < [pathA count]; aSteps++) {
        OFUnit *from = [pathA objectAtIndex:aSteps];
        OFDimensionedValue *b = [from definition];
        OBASSERT([b dimension] == (aSteps+1 < [pathA count]? [pathA objectAtIndex:aSteps+1] : commonUnit));
        aFactors = [OFRationalNumber numberByPerformingOperation:OFArithmeticOperation_Multiply withNumber:aFactors andNumber:[b value]];
    }
    
    // Now aFactors is the conversion factor from aUnit to the common base unit.
    
    if (!bFactors)
        return aFactors;
    else
        return [OFRationalNumber numberByPerformingOperation:OFArithmeticOperation_Divide withNumber:aFactors andNumber:bFactors];
}

- (OFDimensionedValue *)numberByPerformingOperation:(OFArithmeticOperation)op withNumber:(OFDimensionedValue *)v1 andNumber:(OFDimensionedValue *)v2;
{
    if (op == OFArithmeticOperation_Add || op == OFArithmeticOperation_Subtract) {
        if (v1 == nil || v2 == nil)
            OBRejectInvalidCall(self, _cmd, @"Numeric argument is nil");
        
        NSNumber *conversionFactor = [self conformUnit:[v1 dimension] toUnit:[v2 dimension]];
        if (!conversionFactor) {
            // Numbers are not commensurate. Should we raise, return nil, or what?
            return nil;
        }
        NSNumber *v1InV2Units = [OFRationalNumber numberByPerformingOperation:OFArithmeticOperation_Multiply withNumber:[v1 value] andNumber:conversionFactor];
        return [OFDimensionedValue valueWithDimension:[v2 dimension] value:[OFRationalNumber numberByPerformingOperation:op withNumber:v1InV2Units andNumber:[v2 value]]];
    } else {
        OBRejectInvalidCall(self, _cmd, @"Bad opcode (%d)", op);
    }
}

- (NSNumber *)getValue:(OFDimensionedValue *)dim inUnit:(OFUnit *)desiredUnit;
{
    OFUnit *sourceUnit;
    
    sourceUnit = [dim dimension];
    // TODO: If sourceUnit==nil, should we return nil, or should we treat this as a wildcard unit?
    // (We mostly don't treat nil as a wildcard unit elsewhere.)
    if (sourceUnit == nil && desiredUnit != nil)
        return nil;
    if (sourceUnit == desiredUnit)
        return [dim value];
    
    NSNumber *conversionFactor = [self conformUnit:sourceUnit toUnit:desiredUnit];
    if (!conversionFactor)
        return nil;
    
    return [OFRationalNumber numberByPerformingOperation:OFArithmeticOperation_Multiply withNumber:[dim value] andNumber:conversionFactor];    
}

@end

@implementation OFUnits (DelegatesAndDataSources)

@end

@implementation OFUnits (Private)

@end
