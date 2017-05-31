// Copyright 2003-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFXMLElement.h>

#import <Foundation/Foundation.h>

#import <OmniFoundation/CFArray-OFExtensions.h>
#import <OmniFoundation/NSDate-OFExtensions.h>
#import <OmniFoundation/NSString-OFConversion.h>
#import <OmniFoundation/NSString-OFSimpleMatching.h>
#import <OmniFoundation/NSString-OFUnicodeCharacters.h>
#import <OmniFoundation/OFNull.h>
#import <OmniFoundation/OFXMLBuffer.h>
#import <OmniFoundation/OFXMLDocument.h>
#import <OmniFoundation/OFXMLString.h>
#import <OmniFoundation/OFXMLUnparsedElement.h>

#import <OmniBase/OmniBase.h>

RCS_ID("$Id$");

#if OB_ARC
#error Do not convert this to ARC w/o re-checking performance. Last time it was tried, it was noticably slower.
#endif

NS_ASSUME_NONNULL_BEGIN

@implementation OFXMLElement
{
    // Store a single child directly.
    union {
        id _Nullable single;
        NSMutableArray * _Nullable multiple;
    } _child;
    
    // Store a single attribute directly.
    union {
        struct {
            NSString * _Nullable name;
            NSString * _Nullable value;
        } single;
        struct {
            NSMutableArray * _Nullable order;
            NSMutableDictionary * _Nullable values;
        } multiple;
    } _attribute;
    
    BOOL _multipleChildren;
    BOOL _multipleAttributes;
    BOOL _markedAsReferenced;
}

typedef BOOL (^ChildApplier)(id child);
static BOOL EachChild(OFXMLElement *self, ChildApplier NS_NOESCAPE applier)
{
    if (self->_multipleChildren) {
        for (id child in self->_child.multiple) {
            if (!applier(child)) {
                return NO;
            }
        }
    } else if (self->_child.single) {
        return applier(self->_child.single);
    }
    return YES;
}

typedef BOOL (^ChildElementPredicate)(OFXMLElement *child);
static OFXMLElement * _Nullable FirstChildElement(OFXMLElement *self, ChildElementPredicate NS_NOESCAPE predicate)
{
    if (self->_multipleChildren) {
        for (id child in self->_child.multiple) {
            if ([child isKindOfClass:[OFXMLElement class]] && predicate(child)) {
                return child;
            }
        }
    } else if (self->_child.single) {
        id child = self->_child.single;
        if ([child isKindOfClass:[OFXMLElement class]] && predicate(child)) {
            return child;
        }
    }
    return nil;
}

typedef BOOL (^ChildPredicate)(id child);
static id _Nullable FirstChild(OFXMLElement *self, ChildPredicate NS_NOESCAPE predicate)
{
    if (self->_multipleChildren) {
        for (id child in self->_child.multiple) {
            if (predicate(child)) {
                return child;
            }
        }
    } else if (self->_child.single) {
        id child = self->_child.single;
        if (predicate(child)) {
            return child;
        }
    }
    return nil;
}

// Return NO from applier to stop. Whole operation returns YES if enumeration completed.
typedef BOOL (^AttributeApplier)(NSString *name, NSString *value);
static BOOL EachAttribute(OFXMLElement *self, AttributeApplier NS_NOESCAPE applier)
{
    if (self->_multipleAttributes) {
        for (NSString *name in self->_attribute.multiple.order) {
            NSString *value = self->_attribute.multiple.values[name];
            OBASSERT(value);
            if (!applier(name, value)) {
                return NO;
            }
        }
        return YES;
    } else if (self->_attribute.single.name) {
        NSString *value = self->_attribute.single.value;
        OBASSERT(value);
        return applier(self->_attribute.single.name, value);
    } else {
        return YES;
    }
}

static NSUInteger AttributeCount(OFXMLElement *self)
{
    if (self->_multipleAttributes) {
        return [self->_attribute.multiple.order count];
    }
    if (self->_attribute.single.name) {
        return 1;
    }
    return 0;
}
static NSString * _Nullable AttributeNamed(OFXMLElement *self, NSString *name)
{
    if (self->_multipleAttributes) {
        return self->_attribute.multiple.values[name];
    }
    if ([self->_attribute.single.name isEqual:name]) {
        return self->_attribute.single.value;
    }
    return nil;
}
static NSString * _Nullable LastAttributeName(OFXMLElement *self)
{
    if (self->_multipleAttributes) {
        return [self->_attribute.multiple.order lastObject];
    }
    return self->_attribute.single.name;
}

- initWithName:(NSString *)name attributeOrder:(nullable NSMutableArray *)attributeOrder attributes:(nullable NSMutableDictionary *)attributes; // RECIEVER TAKES OWNERSHIP OF attributeOrder and attributes!
{
    self = [super init];

    _name = [name copy];
    
    if (attributeOrder == nil) {
        // OK. Storage will be lazily filled out as needed.
    } else {
        // We take ownership of these instead of making new collections. If there is a single item in the attribute order, the single value initializer would have been a better choice. Maybe add an assert.
        _attribute.multiple.order = [attributeOrder retain];
        _attribute.multiple.values = [attributes retain];
        _multipleAttributes = YES;
    }

    // Children storage is lazily set up as needed.

    return self;
}

- initWithName:(NSString *)name attributeName:(NSString *)attributeName attributeValue:(NSString *)attributeValue;
{
    self = [super init];
    
    _name = [name copy];
    
    _attribute.single.name = [attributeName copy];
    _attribute.single.value = [attributeValue copy];
    
    // Children storage is lazily set up as needed.
    
    return self;
}

- initWithName:(NSString *)name;
{
    return [self initWithName:name attributeOrder:nil attributes:nil];
}

- (void) dealloc;
{
    [_name release];
    
    if (_multipleChildren) {
        [_child.multiple release];
    } else {
        [_child.single release];
    }
    
    if (_multipleAttributes) {
        [_attribute.multiple.order release];
        [_attribute.multiple.values release];
    } else {
        [_attribute.single.name release];
        [_attribute.single.value release];
    }

    [super dealloc];
}

- (id)deepCopy;
{
    return [self deepCopyWithName:_name];
}

- (OFXMLElement *)deepCopyWithName:(NSString *)name;
{
    OFXMLElement *newElement = [[OFXMLElement alloc] initWithName:name];

    if (_multipleAttributes) {
        newElement->_multipleAttributes = YES;
        newElement->_attribute.multiple.order = [_attribute.multiple.order mutableCopy];
        newElement->_attribute.multiple.values = [_attribute.multiple.values mutableCopy];
    } else if (_attribute.single.name) {
        newElement->_attribute.single.name = [_attribute.single.name copy];
        newElement->_attribute.single.value = [_attribute.single.value copy];
    }

    EachChild(self, ^BOOL(id child){
        if ([child isKindOfClass:[OFXMLElement class]]) {
            id copiedChild = [child deepCopy];
            [newElement appendChild:copiedChild];
            [copiedChild release];
        } else {
            [newElement appendChild:child];
        }
        return YES;
    });

    return newElement;
}

- (nullable NSArray *)children;
{
    if (_multipleChildren) {
        OBASSERT(_child.multiple != nil);
        return _child.multiple;
    }
    if (_child.single == nil) {
        return nil;
    }
    
    // Upgrade the children to an array; ideally this would not happen often...
    id child = _child.single; // retained by us.
    _child.multiple = [[NSMutableArray alloc] initWithObjects:&child count:1];
    _multipleChildren = YES;
    [child release];
    
    return _child.multiple;
}

static NSUInteger ChildrenCount(OFXMLElement *self)
{
    if (self->_multipleChildren) {
        return [self->_child.multiple count];
    }
    if (self->_child.single != nil) {
        return 1;
    }
    return 0;
}

- (NSUInteger)childrenCount;
{
    return ChildrenCount(self);
}

- (id)childAtIndex:(NSUInteger)childIndex;
{
    if (_multipleChildren) {
        return _child.multiple[childIndex];
    }

    if (_child.single && childIndex == 0) {
        return _child.single;
    }

    [NSException raise:NSRangeException format:@"The index %lu is out of bounds (element has %lu children).", childIndex, ChildrenCount(self)];
    return nil;
}

static id LastChild(OFXMLElement *self)
{
    if (self->_multipleChildren) {
        return [self->_child.multiple lastObject];
    }
    return self->_child.single;
}

- (id)lastChild;
{
    return LastChild(self);
}

- (NSUInteger)indexOfChildIdenticalTo:(id)child;
{
    if (_multipleChildren) {
        return [_child.multiple indexOfObjectIdenticalTo:child];
    }

    // NSArray would presumably say this if we asked, but maybe `child` should be non-nullable here.
    if (child == nil) {
        return NSNotFound;
    }
    if (_child.single == child) {
        return 0;
    }
    return NSNotFound;
}

- (void)insertChild:(id)child atIndex:(NSUInteger)childIndex;
{
    if (_multipleChildren) {
        [_child.multiple insertObject:child atIndex:childIndex];
    } else {
        if (_child.single) {
            id single = _child.single; // retained by us.
            id children[2];
            if (childIndex == 0) {
                children[0] = child;
                children[1] = single;
            } else if (childIndex == 1) {
                children[0] = single;
                children[1] = child;
            } else {
                [NSException raise:NSRangeException format:@"The index %lu is out of bounds (element has %lu children).", childIndex, ChildrenCount(self)];
            }

            _child.multiple = [[NSMutableArray alloc] initWithObjects:children count:2];
            _multipleChildren = 1;
            [single release];
        } else if (childIndex == 0) {
            _child.single = [child retain];
        } else {
            [NSException raise:NSRangeException format:@"The index %lu is out of bounds (element has %lu children).", childIndex, ChildrenCount(self)];
        }
    }
}

- (void)appendChild:(id)child;  // Either a OFXMLElement or an NSString
{
    OBPRECONDITION([child respondsToSelector:@selector(appendXML:withParentWhiteSpaceBehavior:document:level:error:)]);

    if (_multipleChildren) {
        [_child.multiple addObject:child];
        return;
    }
    
    id single = _child.single;
    if (single) {
        id children[2] = {single, child};
        _child.multiple = [[NSMutableArray alloc] initWithObjects:children count:2];
        _multipleChildren = 1;
        [single release];
    } else {
        _child.single = [child retain];
    }
}

- (void)removeChild:(id)child;
{
    OBPRECONDITION([child isKindOfClass:[NSString class]] || [child isKindOfClass:[OFXMLElement class]]);

    if (_multipleChildren) {
        // We don't downgrade to "single" once we've spent the time to create the array.
        [_child.multiple removeObjectIdenticalTo:child];
        return;
    }

    if (_child.single == child) {
        [_child.single release];
        _child.single = nil;
    }
}

- (void)removeChildAtIndex:(NSUInteger)childIndex;
{
    if (_multipleChildren) {
        [_child.multiple removeObjectAtIndex:childIndex];
        return;
    }
    
    if (_child.single && childIndex == 0) {
        [_child.single release];
        _child.single = nil;
        return;
    }
    
    [NSException raise:NSRangeException format:@"The index %lu is out of bounds (element has %lu children).", childIndex, ChildrenCount(self)];
}

- (void)removeAllChildren;
{
    if (_multipleChildren) {
        [_child.multiple removeAllObjects];
        return;
    }
    
    [_child.single release];
    _child.single = nil;
}

- (void)setChildren:(NSArray *)children;
{
#ifdef OMNI_ASSERTIONS_ON
    {
        for (id child in children)
            OBPRECONDITION([child respondsToSelector:@selector(appendXML:withParentWhiteSpaceBehavior:document:level:error:)]);
    }
#endif

    // Probably not a terribly common operation, so not bothering to check if we can revert to single-child status
    if (_multipleChildren) {
        [_child.multiple setArray:children];
    } else {
        [_child.single release];
        if ([children count] > 1) {
            _child.multiple = [[NSMutableArray alloc] initWithArray:children];
            _multipleChildren = YES;
        } else {
            _child.single = [[children lastObject] retain];
        }
    }
}

- (void)sortChildrenUsingFunction:(NSComparisonResult (*)(id, id, void *))comparator context:(void *)context;
{
    if (_child.multiple) {
        [_child.multiple sortUsingFunction:comparator context:context];
    }
}

- (nullable id)firstChildNamed:(NSString *)childName;
{
    return FirstChild(self, ^(id child){
        // Could be an OFXMLElement or OFXMLUnparsedElement
        if ([child respondsToSelector:@selector(name)]) {
            return [childName isEqual:[child name]];
        }
        return NO;
    });
}

// Does a bunch of -firstChildNamed: calls with each name split by '/'.  This isn't XPath, just a convenience.  Don't put a '/' at the beginning since there is always relative to the receiver.
- (OFXMLElement *)firstChildAtPath:(NSString *)path;
{
    OBPRECONDITION([path hasPrefix:@"/"] == NO);
    
    // Not terribly efficient.  Might use CF later to avoid autoreleases at least.
    NSArray *pathComponents = [path componentsSeparatedByString:@"/"];

    OFXMLElement *currentElement = self;
    for (NSString *pathElement in pathComponents)
        currentElement = [currentElement firstChildNamed:pathElement];
    return currentElement;
}

- (nullable OFXMLElement *)firstChildWithAttribute:(NSString *)attributeName value:(NSString *)value;
{
    OBPRECONDITION(attributeName);
    OBPRECONDITION(value); // Can't look for unset attributes for now.

    return FirstChildElement(self, ^(OFXMLElement *child){
        NSString *attributeValue = [child attributeNamed:attributeName];
        return [value isEqual:attributeValue];
    });
}

// -applyBlock: only iterates the child elements, not strings.
static void ApplyBlock(OFXMLElement *self, void (^block)(id child))
{
    OBPRECONDITION(block != nil);

    block(self);

    if (self->_multipleChildren) {
        for (id child in self->_child.multiple) {
            if ([child isKindOfClass:[OFXMLElement class]]) {
                ApplyBlock(child, block);
            } else {
                block(child);
            }
        }
    } else if (self->_child.single) {
        id child = self->_child.single;
        block(child);
    }
}

- (NSString *)stringContents;
{
    // This isn't optimized for cases like <a/>, <a>xxx</a>, or <a><b>xxx</b></b>, but is only currently used in tests.
    NSMutableString *result = [NSMutableString string];

    // -applyBlock: only hits element children.
    ApplyBlock(self, ^(id child){
        if ([child isKindOfClass:[NSString class]]) {
            [result appendString:child];
        }
    });

    return result;
}

- (NSUInteger)attributeCount;
{
    if (_multipleAttributes) {
        return [_attribute.multiple.order count];
    }
    if (_attribute.single.name) {
        return 1;
    }
    return 0;
}

- (nullable NSArray *)attributeNames;
{
    if (_multipleAttributes) {
        return _attribute.multiple.order;
    }

    if (_attribute.single.name) {
        // In the children case, we upgrade to the "multiple" storage format. Here we're returning an autoreleased array instead of building an array and dictionary. This may require later tuning (though ideally this method wouldn't be called at all.
        return @[_attribute.single.name];
    }

    return nil;
}

- (nullable NSString *)attributeNamed:(NSString *)name;
{
    return AttributeNamed(self, name);
}

- (void)setAttribute:(NSString *)name string:(nullable NSString *)value;
{
    if (_multipleAttributes) {
        OBASSERT([_attribute.multiple.order count] == [_attribute.multiple.values count]);

        if (value) {
            if (![_attribute.multiple.values objectForKey:name])
                [_attribute.multiple.order addObject:name];
            id copy = [value copy];
            [_attribute.multiple.values setObject:copy forKey:name];
            [copy release];
        } else {
            [_attribute.multiple.order removeObject:name];
            [_attribute.multiple.values removeObjectForKey:name];
        }
    } else if (_attribute.single.name) {
        if ([_attribute.single.name isEqual:name]) {
            // Setting or removing our one existing attribute.
            if (value) {
                [value retain];
                [_attribute.single.value release];
                _attribute.single.value = value;
            } else {
                [_attribute.single.name release];
                _attribute.single.name = nil;
                [_attribute.single.value release];
                _attribute.single.value = nil;
            }
        } else if (!value) {
            // Clearing some attribute we don't have. OK.
        } else {
            // Adding a new attribute.
            NSString *keyArray[2] = {_attribute.single.name, name};
            NSString *valueArray[2] = {_attribute.single.value, value};
            NSMutableArray *order = [[NSMutableArray alloc] initWithObjects:keyArray count:2];
            NSMutableDictionary *values = [[NSMutableDictionary alloc] initWithObjects:valueArray forKeys:keyArray count:2];

            [_attribute.single.name release];
            _attribute.single.name = nil;

            [_attribute.single.value release];
            _attribute.single.value = nil;

            _attribute.multiple.order = order;
            _attribute.multiple.values = values;
            _multipleAttributes = YES;
        }
    } else if (value) {
        // First attribute
        _attribute.single.name = [name copy];
        _attribute.single.value = [value copy];
    }
}

- (void) setAttribute: (NSString *) name value: (nullable id) value;
{
    [self setAttribute: name string: [value description]]; // For things like NSNumbers
}

- (void) setAttribute: (NSString *) name integer: (int) value;
{
    NSString *str;
    str = [[NSString alloc] initWithFormat: @"%d", value];
    [self setAttribute: name string: str];
    [str release];
}

- (void) setAttribute: (NSString *) name real: (float) value;  // "%g"
{
    [self setAttribute: name real: value format: @"%g"];
}

- (void) setAttribute: (NSString *) name real: (float) value format: (NSString *) formatString;
{
    NSString *str = [[NSString alloc] initWithFormat: formatString, value];
    [self setAttribute: name string: str];
    [str release];
}

- (void)setAttribute: (NSString *) name double: (double) value;  // "%.15g"
{
    OBASSERT(DBL_DIG == 15);
    [self setAttribute: name double: value format: @"%.15g"];
}

- (void)setAttribute: (NSString *) name double: (double) value format: (NSString *) formatString;
{
    NSString *str = [[NSString alloc] initWithFormat: formatString, value];
    [self setAttribute: name string: str];
    [str release];
}

- (NSString *)stringValueForAttributeNamed:(NSString *)name defaultValue:(NSString *)defaultValue;
{
    NSString *value = [self attributeNamed:name];
    return value ? value : defaultValue;
}

- (int)integerValueForAttributeNamed:(NSString *)name defaultValue:(int)defaultValue;
{
    NSString *value = [self attributeNamed:name];
    return value ? [value intValue] : defaultValue;
}

- (float)realValueForAttributeNamed:(NSString *)name defaultValue:(float)defaultValue;
{
    NSString *value = [self attributeNamed:name];
    return value ? [value floatValue] : defaultValue;
}

- (double)doubleValueForAttributeNamed:(NSString *)name defaultValue:(double)defaultValue;
{
    NSString *value = [self attributeNamed:name];
    return value ? [value doubleValue] : defaultValue;
}

- (OFXMLElement *)appendElement:(NSString *)elementName containingString:(nullable NSString *)contents;
{
    OFXMLElement *child = [[OFXMLElement alloc] initWithName: elementName];

    if (!OFIsEmptyString(contents))
        [child appendChild: contents];
    [self appendChild: child];
    [child release];
    return child;
}

- (OFXMLElement *)appendElement:(NSString *)elementName containingInteger:(int)contents;
{
    NSString *str = [[NSString alloc] initWithFormat: @"%d", contents];
    OFXMLElement *child = [self appendElement: elementName containingString: str];
    [str release];
    return child;
}

- (OFXMLElement *)appendElement:(NSString *)elementName containingReal:(float)contents; // "%g"
{
    return [self appendElement: elementName containingReal: contents format: @"%g"];
}

- (OFXMLElement *)appendElement:(NSString *)elementName containingReal:(float)contents format:(NSString *)formatString;
{
    NSString *str = [[NSString alloc] initWithFormat: formatString, contents];
    OFXMLElement *child = [self appendElement: elementName containingString: str];
    [str release];
    return child;
}

- (OFXMLElement *)appendElement:(NSString *)elementName containingDouble:(double)contents; // "%.15g"
{
    OBASSERT(DBL_DIG == 15);
    return [self appendElement: elementName containingDouble: contents format: @"%.15g"];
}

- (OFXMLElement *)appendElement:(NSString *)elementName containingDouble:(double) contents format:(NSString *) formatString;
{
    NSString *str = [[NSString alloc] initWithFormat: formatString, contents];
    OFXMLElement *child = [self appendElement: elementName containingString: str];
    [str release];
    return child;
}

- (OFXMLElement *)appendElement:(NSString *)elementName containingDate:(NSDate *)date;
{
    return [self appendElement:elementName containingString:[date xmlString]];
}

- (void)removeAttributeNamed:(NSString *)name;
{
    [self setAttribute:name string:nil];
}

- (void)markAsReferenced;
{
    _markedAsReferenced = 1;
}

- (BOOL)shouldIgnore;
{
    if (_ignoreUnlessReferenced)
        return !_markedAsReferenced;
    return NO;
}

- (void)applyFunction:(OFXMLElementApplier)applier context:(void *)context;
{
    // We are an element
    applier(self, context);
    
    if (self->_multipleChildren) {
        for (id child in self->_child.multiple) {
            if ([child isKindOfClass:[OFXMLElement class]]) {
                [child applyFunction:applier context:context];
            }
        }
    } else if (self->_child.single) {
        id child = self->_child.single;
        if ([child isKindOfClass:[OFXMLElement class]]) {
            [child applyFunction:applier context:context];
        }
    }
}

- (void)applyBlock:(OFXMLElementApplierBlock NS_NOESCAPE)applierBlock;
{
    OBPRECONDITION(applierBlock != nil);
    
    applierBlock(self);

    if (self->_multipleChildren) {
        for (id child in self->_child.multiple) {
            if ([child isKindOfClass:[OFXMLElement class]]) {
                [child applyBlock:applierBlock];
            }
        }
    } else if (self->_child.single) {
        id child = self->_child.single;
        if ([child isKindOfClass:[OFXMLElement class]]) {
            [child applyBlock:applierBlock];
        }
    }
}

- (nullable NSData *)xmlDataAsFragment:(NSError **)outError; // Mostly useful for debugging since this assumes no whitespace is important
{
    OFXMLWhitespaceBehavior *whitespace = [[OFXMLWhitespaceBehavior alloc] init];
    [whitespace setBehavior:OFXMLWhitespaceBehaviorTypeIgnore forElementName:[self name]];
    
    NSError *error = nil;
    OFXMLDocument *doc = [[OFXMLDocument alloc] initWithRootElement:self dtdSystemID:NULL dtdPublicID:nil whitespaceBehavior:whitespace stringEncoding:kCFStringEncodingUTF8 error:&error];
    if (!doc) {
        OBASSERT_NOT_REACHED("We always pass the same input parameters, so this should never error out");
    }
    
    [whitespace release];
    
    NSData *xml = [doc xmlDataAsFragment:outError];
    [doc release];
    
    return xml;
}

#pragma mark - NSObject (OFXMLWriting)

- (BOOL)appendXML:(struct _OFXMLBuffer *)xml withParentWhiteSpaceBehavior:(OFXMLWhitespaceBehaviorType)parentBehavior document:(OFXMLDocument *)doc level:(unsigned int)level error:(NSError **)outError;
{
    OFXMLWhitespaceBehaviorType whitespaceBehavior;

    if (_ignoreUnlessReferenced && !_markedAsReferenced)
        return YES; // trivial success

    whitespaceBehavior = [[doc whitespaceBehavior] behaviorForElementName: _name];
    if (whitespaceBehavior == OFXMLWhitespaceBehaviorTypeAuto)
        whitespaceBehavior = parentBehavior;

    OFXMLBufferAppendUTF8CString(xml, "<");
    OFXMLBufferAppendString(xml, (__bridge CFStringRef)_name);

    // Quote the attribute values
    CFStringEncoding encoding = [doc stringEncoding];

    EachAttribute(self, ^(NSString *name, NSString *value){
        OBASSERT(value); // If we write out <element key>, libxml will hate us. This shouldn't happen, but it has once.
        if (!value)
            return YES;

        OBASSERT(![value containsCharacterInSet:[NSString discouragedXMLCharacterSet]]);

        OFXMLBufferAppendUTF8CString(xml, " ");
        OFXMLBufferAppendString(xml, (__bridge CFStringRef)name);

        if (value) {
            OFXMLBufferAppendUTF8CString(xml, "=\"");
            // OPML includes user text in attributes, which may contain newlines, which should be converted to &#10;.
            NSString *quotedString = OFXMLCreateStringWithEntityReferencesInCFEncoding(value, OFXMLBasicEntityMask | OFXMLNewlineEntityMask, @"&#10;", encoding);
            OFXMLBufferAppendString(xml, (__bridge CFStringRef)quotedString);
            [quotedString release];
            OFXMLBufferAppendUTF8CString(xml, "\"");
        }
        return YES;
    });

    __block BOOL hasWrittenChild = NO;
    __block BOOL doIntenting = NO;
    
    // See if any of our children are non-ignored and use this for isEmpty instead of the plain count
    BOOL success = EachChild(self, ^BOOL(id child){
        if ([child respondsToSelector:@selector(shouldIgnore)] && [child shouldIgnore])
            return YES;
        
        // If we have actual element children and whitespace isn't important for this node, do some formatting.
        // We will produce output that is a little strange for something like '<x>foo<y/></x>' or any other mix of string and element children, but usually whitespace is important in this case and it won't be an issue.
        if (whitespaceBehavior == OFXMLWhitespaceBehaviorTypeIgnore)  {
            doIntenting = [child xmlRepresentationCanContainChildren];
        }

        // Close off the parent tag if this is the first child
        if (!hasWrittenChild)
            OFXMLBufferAppendUTF8CString(xml, ">");
        
        if (doIntenting) {
            OFXMLBufferAppendUTF8CString(xml, "\n");
            OFXMLBufferAppendSpaces(xml, 2*(level + 1));
        }

        if (![child appendXML:xml withParentWhiteSpaceBehavior:whitespaceBehavior document:doc level:level+1 error:outError])
            return NO;

        hasWrittenChild = YES;
        return YES;
    });

    if (!success) {
        return NO;
    }

    if (doIntenting) {
        OFXMLBufferAppendUTF8CString(xml, "\n");
        OFXMLBufferAppendSpaces(xml, 2*level);
    }
    
    if (hasWrittenChild) {
        OFXMLBufferAppendUTF8CString(xml, "</");
        OFXMLBufferAppendString(xml, (__bridge CFStringRef)_name);
        OFXMLBufferAppendUTF8CString(xml, ">");
    } else
        OFXMLBufferAppendUTF8CString(xml, "/>");
    
    return YES;
}

- (BOOL)xmlRepresentationCanContainChildren;
{
    return YES;
}

#pragma mark - Comparison

- (BOOL)isEqual:(id)otherObject;
{
    // We don't consider OFXMLUnparsedElement the same, even if it would produce the same output. Not sure if this is a bug; let's catch this case here to see if it ever hits.
    OBPRECONDITION(![otherObject isKindOfClass:[OFXMLUnparsedElement class]]);
    if (![otherObject isKindOfClass:[OFXMLElement class]])
        return NO;
    
    OFXMLElement *otherElement = otherObject;
    
    if (OFNOTEQUAL(_name, otherElement->_name))
        return NO;
    
    // Allow nil to be equal to empty
    NSUInteger attributeCount = AttributeCount(self);
    NSUInteger otherAttributeCount = AttributeCount(otherElement);

    if (attributeCount != otherAttributeCount) {
        return NO;
    }
    if (attributeCount > 0) {
        if (attributeCount == 1) {
            // Either could be in 'multiple' storage format.
            NSString *name = LastAttributeName(self);
            if (![AttributeNamed(self, name) isEqual:AttributeNamed(otherElement, name)]) {
                return NO;
            }
        } else {
            BOOL equalAttributes = EachAttribute(self, ^BOOL(NSString *name, NSString *value) {
                return [AttributeNamed(otherElement, name) isEqual:value];
            });
            if (!equalAttributes) {
                return NO;
            }
        }
    }

    NSUInteger childrenCount = ChildrenCount(self);
    NSUInteger otherChildrenCount = ChildrenCount(otherElement);

    if (childrenCount != otherChildrenCount) {
        return NO;
    } else {
        if (childrenCount > 1) {
            // Since the counts are equal, both elements must have arrays
            OBASSERT(self->_multipleChildren);
            OBASSERT(otherElement->_multipleChildren);
            if (OFNOTEQUAL(_child.multiple, otherElement->_child.multiple)) {
                return NO;
            }
        } else if (childrenCount == 1) {
            // Either might have a single or multiple, so use the wrapper function.
            if (![LastChild(self) isEqual:LastChild(otherElement)]) {
                return NO;
            }
        } else {
            // Both zero, OK.
        }
    }

    // Ignoring the flags
    return YES;
}

#pragma mark - Debugging

- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *debugDictionary;

    debugDictionary = [super debugDictionary];
    [debugDictionary setObject: _name forKey: @"_name"];

    if (_multipleChildren) {
        [debugDictionary setObject: _child.multiple forKey: @"_children"];
    } else if (_child.single) {
        [debugDictionary setObject: @[_child.single] forKey: @"_children"];
    }

    if (_multipleAttributes) {
        [debugDictionary setObject: _attribute.multiple.order forKey: @"_attributeOrder"];
        [debugDictionary setObject: _attribute.multiple.values forKey: @"_attributes"];
    } else if (_attribute.single.name) {
        [debugDictionary setObject: @[_attribute.single.name] forKey: @"_attributeOrder"];
        [debugDictionary setObject: @{_attribute.single.name: _attribute.single.value} forKey: @"_attributes"];
    }

    return debugDictionary;
}

- (NSString *)debugDescription;
{
    NSError *error = nil;
    NSData *data = [self xmlDataAsFragment:&error];
    if (!data) {
        NSLog(@"Error converting element to data: %@", [error toPropertyList]);
        return [error description] ?: @"Generic XML data fragment conversion error";
    }
    
    return [NSString stringWithData:data encoding:NSUTF8StringEncoding];
}

@end


@implementation NSObject (OFXMLWritingPartial)

#if 0 // NOT implementing this since our precondition in -appendChild: is easier this way.
- (BOOL)appendXML:(struct _OFXMLBuffer *)xml withParentWhiteSpaceBehavior:(OFXMLWhitespaceBehaviorType)parentBehavior document:(OFXMLDocument *)doc level:(unsigned int)level error:(NSError **)outError;
{
    OBRejectUnusedImplementation([self class], _cmd);
}
#endif

- (BOOL)xmlRepresentationCanContainChildren;
{
    return NO;
}

@end

NS_ASSUME_NONNULL_END
