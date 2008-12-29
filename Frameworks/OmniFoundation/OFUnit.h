// Copyright 2005-2006 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFObject.h>
#import <CoreServices/CoreServices.h>

@class NSScanner, NSSet, NSString;
@class OFUnit, OFUnits, OFDimensionedValue;

@interface OFUnit : OFObject
{
    NSString *name;            // Canonical name for definition: not localized; may not be nil
    NSString *abbreviation;    // Canonical abbreviation for interchange: not localized; may be nil
    NSString *selectionName;   // A name by which this unit can be selected from a popup, etc.; localized
    NSString *displayFormat;   // Localized display format string; defaults to "%@ xxx" where xxx is the storage name
    
    NSSet *scanSuffixes;       // Scannable representations (localized)
    
    OFUnit *smallerUnit;       // Conventional next-smallest unit to use for display
//    NSArray *rulerSteps;       // Conventional subdivision and superdivision for NSRulerView
    OFUnit *postfixUnit;       // foo
    
    OFDimensionedValue *definition;        // Definition of this unit (base unit and conversion factor)
    BOOL isGroupBase;          // Is this the fundamental unit of a convention group?
    
    FourCharCode ascrUnit;     // Some units are representable in AppleScript as typed doubles (see AERegistry.h)
}

// -readFromPropertyList:container: may be called more than once; new information will be merged. This is used for loading the localized names of units.
- (BOOL)readFromPropertyList:(NSDictionary *)plist container:(OFUnits *)units;
- (NSMutableDictionary *)propertyListRepresentationInContainer:(OFUnits *)units base:(OFUnit *)baseDefinition;

- (NSString *)name;    // The canonical, nonlocalized name of this unit (e.g. "inches" or "tick feet")
- (NSString *)abbreviation;  // The canonical, nonlocalized abbreviation for this unit (e.g. "in" or "km")
- (BOOL)hasName:(NSString *)anyName;  // Whether any of the localized, scannable names of this unit correspond to this string ("in", "inches", "'")
- (OFDimensionedValue *)definition;

- (NSString *)selectionName;  // A name which could be put on e.g. a units popup (localized)
- (NSString *)displayFormat;  // TODO: Separate into methods for editing, for storage, for display (attributed string?)

- (OFUnit *)postfixUnit;
- (FourCharCode)typeCodeValue;

@end

@interface OFUnit (OFUnitOptionalMethods)

- (BOOL)scanValue:(OFDimensionedValue **)aValue fromScanner:(NSScanner *)scan;

@end

