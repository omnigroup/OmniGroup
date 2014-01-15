// Copyright 2000-2005, 2007-2008, 2010, 2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <AppKit/NSColor.h>
#import <OmniBase/OBUtilities.h>

@class NSDictionary, NSMutableDictionary;
@class OFXMLDocument, OFXMLCursor;

@interface NSColor (OAExtensions)

+ (NSColor *)colorFromPropertyListRepresentation:(NSDictionary *)dict; // When specifying colors by component, values for abbreviated keys (@"r", @"g", etc.) are floats in [0, 1]. Spelled-out keys (@"red", @"green") are integers in the natural range of the value ([0, 255] for RGB, [0, 100] for HSB and CMYK, [0, 100] for alpha).

- (NSMutableDictionary *)propertyListRepresentationWithStringComponentsOmittingDefaultValues:(BOOL)omittingDefaultValues;
- (NSMutableDictionary *)propertyListRepresentationWithNumberComponentsOmittingDefaultValues:(BOOL)omittingDefaultValues;
- (NSMutableDictionary *)propertyListRepresentation; // deprecated

- (BOOL)isSimilarToColor:(NSColor *)color;
- (BOOL)isPatternSimilarToColorPattern:(NSColor *)color;
- (NSData *)patternImagePNGData;

- (NSString *)similarColorNameFromColorLists;
+ (NSColor *)colorWithSimilarName:(NSString *)aName;

- (CGColorRef)newCGColor CF_RETURNS_RETAINED;

+ (NSColor *)colorFromCGColor:(CGColorRef)colorRef;
- (CGColorRef)newCGColorWithCGColorSpace:(CGColorSpaceRef)destinationColorSpace CF_RETURNS_RETAINED;

// XML Archiving
+ (NSString *)xmlElementName;
- (void) appendXML:(OFXMLDocument *)doc;
+ (NSColor *)colorFromXML:(OFXMLCursor *)cursor;
+ (NSColor *)colorFromXMLTreeRef:(CFXMLTreeRef)treeRef OB_DEPRECATED_ATTRIBUTE;

@end

// XML Archiving user object key
extern NSString * const OAColorXMLAdditionalColorSpace;

// Value transformers
extern NSString * const OAColorToPropertyListTransformerName;
extern NSString * const OABooleanToControlColorTransformerName;
extern NSString * const OANegateBooleanToControlColorTransformerName;

// Takes rgba in 0..1.  Doubles so that we don't get warnings when using constants about 64->32 implicit casts.
static inline NSColor *OARGBA(double r, double g, double b, double a)
{
    return [NSColor colorWithCalibratedRed:(CGFloat)r green:(CGFloat)g blue:(CGFloat)b alpha:(CGFloat)a];
}
