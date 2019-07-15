// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OAColor.h>

@class OFXMLDocument, OFXMLCursor;

@interface OAColor (XML)

+ (BOOL)colorSpaceOfPropertyListRepresentation:(NSDictionary *)dict colorSpace:(OAColorSpace *)colorSpaceOutRef;
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

// A user key on OFXMLDocument that can be set to specify a NSValueTransfomer to convert in-memory colors to another color for the external representation (still a color, but possibly in a different color space). -transformedValue: is called to convert from the in-memory color to the external representation, and -reverseTransformedValue: is used to convert from the external representation to the in-memory representation. If either transform returns nil, the original color is used. This is supported for both OAColor (on iOS and macOS) and NSColor (on macOS).
extern NSString * const OAColorExternalRepresentationTransformerUserKey;
