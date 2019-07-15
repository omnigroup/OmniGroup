// Copyright 2003-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFObject.h>
#import <OmniFoundation/OFXMLWhitespaceBehavior.h>
#import <OmniFoundation/OFXMLBuffer.h>
#import <OmniBase/OBUtilities.h>

@class NSArray, NSMutableArray, NSDate, NSData, NSMutableDictionary, NSMutableString, NSError;
@class OFXMLDocument, OFXMLElement;

NS_ASSUME_NONNULL_BEGIN

typedef void (*OFXMLElementApplier)(OFXMLElement *element, void *context);
typedef void (^OFXMLElementApplierBlock)(OFXMLElement *element);

@interface OFXMLElement : OFObject

- (instancetype)initWithName:(NSString *)name attributeOrder:(nullable NSMutableArray *)attributeOrder attributes:(nullable NSMutableDictionary *)attributes; // RECEIVER TAKES OWNERSHIP OF attributeOrder and attributes!
- (instancetype)initWithName:(NSString *)name attributeName:(NSString *)attributeName attributeValue:(NSString *)attributeValue;
- (instancetype)initWithName:(NSString *)name;


- (id)deepCopy NS_RETURNS_RETAINED;
- (OFXMLElement *)deepCopyWithName:(NSString *)name NS_RETURNS_RETAINED;

@property(nonatomic,readonly) NSString *name;

// 1 NSString, or any number of OFXMLElements or OFXMLUnparsedElements
@property(nullable,nonatomic,readonly) NSArray *children;
@property(nonatomic,readonly) NSUInteger childrenCount;
- (id)childAtIndex:(NSUInteger)childIndex;
@property(nonatomic,readonly) id lastChild;
- (NSUInteger)indexOfChildIdenticalTo:(id)child;
- (void)insertChild:(id)child atIndex:(NSUInteger)childIndex;
- (void)appendChild:(id) child;  // Either a OFXMLElement or an NSString
- (void)removeChild:(id) child;
- (void)removeChildAtIndex:(NSUInteger)childIndex;
- (void)removeAllChildren;
- (void)setChildren:(NSArray *)children;
- (void)sortChildrenUsingFunction:(NSComparisonResult (*)(id, id, void *))comparator context:(void *)context;
- (nullable OFXMLElement *)firstChildNamed:(NSString *)childName;
- (OFXMLElement *)firstChildAtPath:(NSString *)path;
- (nullable OFXMLElement *)firstChildWithAttribute:(NSString *)attribute value:(NSString *)value;

// Gathers all the immediate and descendent string children and concatenates them into a single string.
// This will ignore any children that are unparsed XML elements.
@property(nonatomic, readonly) NSString *stringContents;

@property(nonatomic,assign) BOOL ignoreUnlessReferenced;
- (void)markAsReferenced;
@property(nonatomic,readonly) BOOL shouldIgnore;

@property(nonatomic,readonly) NSUInteger attributeCount;
@property(nullable,nonatomic,readonly) NSArray<NSString *> *attributeNames;
- (nullable NSString *) attributeNamed: (NSString *) name;
- (void) setAttribute: (NSString *) name string: (nullable NSString *) value;
- (void) setAttribute: (NSString *) name value: (nullable id) value;
- (void) setAttribute: (NSString *) name integer: (int) value;
- (void) setAttribute: (NSString *) name real: (float) value;  // "%g"
- (void) setAttribute: (NSString *) name real: (float) value format: (NSString *) formatString;
- (void) setAttribute: (NSString *) name double: (double) value;  // "%.15g"
- (void) setAttribute: (NSString *) name double: (double) value format: (NSString *) formatString;

- (NSString *)stringValueForAttributeNamed:(NSString *)name defaultValue:(NSString *)defaultValue;
- (int)integerValueForAttributeNamed:(NSString *)name defaultValue:(int)defaultValue;
- (float)realValueForAttributeNamed:(NSString *)name defaultValue:(float)defaultValue;
- (double)doubleValueForAttributeNamed:(NSString *)name defaultValue:(double)defaultValue;

- (OFXMLElement *)appendElement:(NSString *)elementName containingString:(nullable NSString *)contents;
- (OFXMLElement *)appendElement:(NSString *)elementName containingInteger:(int)contents;
- (OFXMLElement *)appendElement:(NSString *)elementName containingReal:(float)contents; // "%g"
- (OFXMLElement *)appendElement:(NSString *)elementName containingReal:(float)contents format:(NSString *)formatString;
- (OFXMLElement *)appendElement:(NSString *)elementName containingDouble:(double)contents; // "%.15g"
- (OFXMLElement *)appendElement:(NSString *)elementName containingDouble:(double) contents format:(NSString *) formatString;
- (OFXMLElement *)appendElement:(NSString *)elementName containingDate:(NSDate *)date;
- (void) removeAttributeNamed: (NSString *) name;

- (void)applyFunction:(OFXMLElementApplier)applier context:(void *)context;
- (void)applyBlock:(OFXMLElementApplierBlock NS_NOESCAPE)applierBlock; // Only OFXMLElements are passed to the block.
- (void)applyBlockToAllChildren:(void (^ NS_NOESCAPE)(id child))applierBlock; // All children are passed to the block (strings, frozen/unparsed elements).

- (nullable NSData *)xmlDataAsFragment:(NSError **)outError; // Mostly useful for debugging since this assumes no whitespace is important

// Debugging
- (NSMutableDictionary *)debugDictionary;
- (NSString *)debugDescription;

@end

@interface NSObject (OFXMLWriting)
- (BOOL)appendXML:(OFXMLBuffer)xml withParentWhiteSpaceBehavior:(OFXMLWhitespaceBehaviorType)parentBehavior document:(OFXMLDocument *)doc level:(unsigned int)level error:(NSError **)outError;
- (BOOL)xmlRepresentationCanContainChildren;
@end

NS_ASSUME_NONNULL_END
