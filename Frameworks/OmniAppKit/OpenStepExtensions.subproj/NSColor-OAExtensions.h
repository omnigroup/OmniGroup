// Copyright 2000-2005, 2007-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <AppKit/NSColor.h>

@class NSDictionary, NSMutableDictionary;
@class OFXMLDocument, OFXMLCursor;

@interface NSColor (OAExtensions)

+ (NSColor *)colorFromPropertyListRepresentation:(NSDictionary *)dict;

- (NSMutableDictionary *)propertyListRepresentationWithStringComponentsOmittingDefaultValues:(BOOL)omittingDefaultValues;
- (NSMutableDictionary *)propertyListRepresentationWithNumberComponentsOmittingDefaultValues:(BOOL)omittingDefaultValues;
- (NSMutableDictionary *)propertyListRepresentation; // deprecated

- (BOOL)isSimilarToColor:(NSColor *)color;
- (NSData *)patternImagePNGData;

- (NSString *)similarColorNameFromColorLists;
+ (NSColor *)colorWithSimilarName:(NSString *)aName;

// XML Archiving
+ (NSString *)xmlElementName;
- (void) appendXML:(OFXMLDocument *)doc;
+ (NSColor *)colorFromXML:(OFXMLCursor *)cursor;
+ (NSColor *)colorFromXMLTreeRef:(CFXMLTreeRef)treeRef;

@end

// XML Archiving user object key
extern NSString * const OAColorXMLAdditionalColorSpace;

// Value transformers
extern NSString * const OAColorToPropertyListTransformerName;
extern NSString * const OABooleanToControlColorTransformerName;
extern NSString * const OANegateBooleanToControlColorTransformerName;
