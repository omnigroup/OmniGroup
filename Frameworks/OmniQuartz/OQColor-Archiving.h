// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniQuartz/OQColor.h>

@class OFXMLDocument, OFXMLCursor;

@interface OQColor (XML)

+ (OQColor *)colorFromPropertyListRepresentation:(NSDictionary *)dict;
- (NSMutableDictionary *)propertyListRepresentationWithStringComponentsOmittingDefaultValues:(BOOL)omittingDefaultValues;
- (NSMutableDictionary *)propertyListRepresentationWithNumberComponentsOmittingDefaultValues:(BOOL)omittingDefaultValues;
- (NSMutableDictionary *)propertyListRepresentation; // deprecated

+ (NSString *)xmlElementName;
+ (OQColor *)colorFromXML:(OFXMLCursor *)cursor;
- (void)appendXML:(OFXMLDocument *)doc;

@end
