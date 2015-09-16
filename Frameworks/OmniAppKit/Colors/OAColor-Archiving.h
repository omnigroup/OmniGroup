// Copyright 2010-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniAppKit/OAColor.h>

@class OFXMLDocument, OFXMLCursor;

@interface OAColor (XML)

+ (OAColor *)colorFromPropertyListRepresentation:(NSDictionary *)dict;
- (NSMutableDictionary *)propertyListRepresentationWithStringComponentsOmittingDefaultValues:(BOOL)omittingDefaultValues;
- (NSMutableDictionary *)propertyListRepresentationWithNumberComponentsOmittingDefaultValues:(BOOL)omittingDefaultValues;
- (NSMutableDictionary *)propertyListRepresentation; // deprecated

+ (NSString *)xmlElementName;
+ (OAColor *)colorFromXML:(OFXMLCursor *)cursor;
- (void)appendXML:(OFXMLDocument *)doc;

@end

// Extend the OAMakeUIColor overridable function
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
@interface UIColor (OAColorArchiving)
+ (instancetype)colorFromPropertyListRepresentation:(NSDictionary *)plist;
@end

static inline UIColor * __attribute__((overloadable)) OAMakeUIColor(NSDictionary *plist)
{
    return [[OAColor colorFromPropertyListRepresentation:plist] toColor];
}
#endif
