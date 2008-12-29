// Copyright 2005-2006 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFObject.h>
#import <OmniFoundation/NSNumber-OFExtensions.h>

@class NSArray, NSBundle, NSString;   // Foundation
@class OFUnit, OFDimensionedValue;    // OmniFoundation

@interface OFUnits : NSObject
{
    NSArray *units;
}

+ (OFUnits *)loadUnitsNamed:(NSString *)resourceName inBundle:(NSBundle *)aBundle;

- propertyListRepresentation;
- propertyListRepresentationWithBase:(OFUnits *)base;

- (void)readPropertyList:(NSArray *)ul;

- (NSArray *)units;

- (NSString *)nameOfUnit:(OFUnit *)aUnit;
- (OFUnit *)unitByName:(NSString *)storageName;

- (OFUnit *)unitFromString:(NSString *)inputString;

- (NSString *)storageStringForValue:(OFDimensionedValue *)dim;

- (NSNumber *)conformUnit:(OFUnit *)aUnit toUnit:(OFUnit *)anotherUnit;

- (OFDimensionedValue *)numberByPerformingOperation:(OFArithmeticOperation)op withNumber:(OFDimensionedValue *)v1 andNumber:(OFDimensionedValue *)v2;

- (NSNumber *)getValue:(OFDimensionedValue *)dim inUnit:(OFUnit *)unitName; // Convenience

@end

@interface OFUnits (InputParsing)

- (OFDimensionedValue *)parseString:(NSString *)str defaultUnit:(OFUnit *)defaultUnit;

@end

// Informal delegate method:
//   - (OFDimensionedValue *)temporaryDefinitionForUnit:(OFUnit *)aUnit of:(OFUnits *)container;
