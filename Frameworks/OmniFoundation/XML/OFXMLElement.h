// Copyright 2003-2005, 2007-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFObject.h>

#import <OmniFoundation/OFXMLWhitespaceBehavior.h>

@class NSArray, NSMutableArray, NSMutableDictionary, NSMutableString, NSError;
@class OFXMLDocument, OFXMLElement;

typedef void (*OFXMLElementApplier)(OFXMLElement *element, void *context);


@interface OFXMLElement : OFObject
{
    NSString *_name;
    NSMutableArray *_children;
    NSMutableArray *_attributeOrder;
    NSMutableDictionary *_attributes;
    struct {
        unsigned int ignoreUnlessReferenced : 1;
        unsigned int markedAsReferenced     : 1;
    } _flags;
}

- initWithName:(NSString *)name attributeOrder:(NSMutableArray *)attributeOrder attributes:(NSMutableDictionary *)attributes; // RECIEVER TAKES OWNERSHIP OF attributeOrder and attributes!
- initWithName:(NSString *)name;


- (id)deepCopy;
- (OFXMLElement *)deepCopyWithName:(NSString *)name;

- (NSString *) name;
- (NSArray *) children;
- (unsigned int)childrenCount;
- (id) childAtIndex: (NSUInteger) childIndex;
- (id) lastChild;
- (unsigned int)indexOfChildIdenticalTo:(id)child;
- (void)insertChild:(id)child atIndex:(unsigned int)childIndex;
- (void) appendChild: (id) child;  // Either a OFXMLElement or an NSString
- (void) removeChild: (id) child;
- (void) removeChildAtIndex: (unsigned int) childIndex;
- (void)removeAllChildren;
- (void)setChildren:(NSArray *)children;
- (void)sortChildrenUsingFunction:(NSComparisonResult (*)(id, id, void *))comparator context:(void *)context;
- (OFXMLElement *)firstChildNamed:(NSString *)childName;
- (OFXMLElement *)firstChildAtPath:(NSString *)path;
- (OFXMLElement *)firstChildWithAttribute:(NSString *)attribute value:(NSString *)value;

- (void)setIgnoreUnlessReferenced:(BOOL)yn;
- (BOOL)ignoreUnlessReferenced;
- (void)markAsReferenced;
- (BOOL)shouldIgnore;

- (NSArray *) attributeNames;
- (NSString *) attributeNamed: (NSString *) name;
- (void) setAttribute: (NSString *) name string: (NSString *) value;
- (void) setAttribute: (NSString *) name value: (id) value;
- (void) setAttribute: (NSString *) name integer: (int) value;
- (void) setAttribute: (NSString *) name integer: (int) value;
- (void) setAttribute: (NSString *) name real: (float) value;  // "%g"
- (void) setAttribute: (NSString *) name real: (float) value format: (NSString *) formatString;

- (NSString *)stringValueForAttributeNamed:(NSString *)name defaultValue:(NSString *)defaultValue;
- (int)integerValueForAttributeNamed:(NSString *)name defaultValue:(int)defaultValue;
- (float)realValueForAttributeNamed:(NSString *)name defaultValue:(float)defaultValue;

- (OFXMLElement *)appendElement:(NSString *)elementName containingString:(NSString *)contents;
- (OFXMLElement *)appendElement:(NSString *)elementName containingInteger:(int)contents;
- (OFXMLElement *)appendElement:(NSString *)elementName containingReal:(float)contents; // "%g"
- (OFXMLElement *)appendElement:(NSString *)elementName containingReal:(float)contents format:(NSString *)formatString;
- (OFXMLElement *)appendElement:(NSString *)elementName containingDate:(NSDate *)date;
- (void) removeAttributeNamed: (NSString *) name;
- (void)sortAttributesUsingFunction:(NSComparisonResult (*)(id, id, void *))comparator context:(void *)context;
- (void)sortAttributesUsingSelector:(SEL)comparator;

- (void)applyFunction:(OFXMLElementApplier)applier context:(void *)context;

- (NSData *)xmlDataAsFragment:(NSError **)outError; // Mostly useful for debugging since this assumes no whitespace is important

// Debugging
- (NSMutableDictionary *)debugDictionary;
- (NSString *)debugDescription;

@end

@interface NSObject (OFXMLWriting)
- (BOOL)appendXML:(struct _OFXMLBuffer *)xml withParentWhiteSpaceBehavior:(OFXMLWhitespaceBehaviorType)parentBehavior document:(OFXMLDocument *)doc level:(unsigned int)level error:(NSError **)outError;
- (BOOL)xmlRepresentationCanContainChildren;
- (NSObject *)copyFrozenElement;
@end
