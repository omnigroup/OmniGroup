// Copyright 2003-2005, 2007-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFXMLElement.h>

#import <OmniFoundation/OFXMLDocument.h>
#import <OmniFoundation/OFXMLString.h>
#import <OmniFoundation/NSString-OFSimpleMatching.h>
#import <OmniFoundation/NSString-OFConversion.h>
#import <OmniFoundation/CFArray-OFExtensions.h>
#import <OmniFoundation/NSDate-OFExtensions.h>

#import <OmniFoundation/OFXMLBuffer.h>
#import <OmniFoundation/OFXMLFrozenElement.h>

RCS_ID("$Id$");

@implementation OFXMLElement

- initWithName:(NSString *)name attributeOrder:(NSMutableArray *)attributeOrder attributes:(NSMutableDictionary *)attributes; // RECIEVER TAKES OWNERSHIP OF attributeOrder and attributes!
{
    _name = [name copy];
    
    // We take ownership of these instead of making new collections.  If nil, they'll be lazily created.
    _attributeOrder = [attributeOrder retain];
    _attributes = [attributes retain];
    
    // _children is lazily allocated

    return self;
}

- initWithName:(NSString *)name;
{
    return [self initWithName:name attributeOrder:nil attributes:nil];
}

- (void) dealloc;
{
    [_name release];
    [_children release];
    [_attributeOrder release];
    [_attributes release];
    [super dealloc];
}

- (id)deepCopy;
{
    return [self deepCopyWithName:_name];
}

- (OFXMLElement *)deepCopyWithName:(NSString *)name;
{
    OFXMLElement *newElement = [[OFXMLElement alloc] initWithName:name];
    
    if (_attributeOrder != nil)
        newElement->_attributeOrder = [[NSMutableArray alloc] initWithArray:_attributeOrder];
    
    if (_attributes != nil)
        newElement->_attributes = [_attributes mutableCopy];	// don't need a deep copy because all the attributes are non-mutable strings, but we don need a unique copy of the attributes dictionary

    unsigned int childIndex, childCount = [_children count];
    for (childIndex = 0; childIndex < childCount; childIndex++) {
        BOOL copied = NO;

        id child = [_children objectAtIndex:childIndex];
        if ([child isKindOfClass:[OFXMLElement class]]) {
            child = [child deepCopy];
            copied = YES;
        }
        [newElement appendChild:child];
        if (copied)
            [child release];
    }

    return newElement;
}

- (NSString *)name;
{
    return _name;
}

- (NSArray *)children;
{
    return _children;
}

- (unsigned int)childrenCount;
{
    return [_children count];
}

- (id) childAtIndex: (NSUInteger) childIndex;
{
    return [_children objectAtIndex: childIndex];
}

- (id) lastChild;
{
    return [_children lastObject];
}

- (unsigned int)indexOfChildIdenticalTo:(id)child;
{
    return [_children indexOfObjectIdenticalTo:child];
}

- (void)insertChild:(id)child atIndex:(unsigned int)childIndex;
{
    if (!_children) {
        OBASSERT(childIndex == 0); // Else, certain doom
        _children = [[NSMutableArray alloc] initWithObjects:&child count:1];
    }
    [_children insertObject:child atIndex:childIndex];
}

- (void)appendChild:(id)child;  // Either a OFXMLElement or an NSString
{
    OBPRECONDITION([child respondsToSelector:@selector(appendXML:withParentWhiteSpaceBehavior:document:level:error:)]);

    if (!_children)
	// This happens a lot; avoid the placeholder goo
	_children = (NSMutableArray *)CFArrayCreateMutable(kCFAllocatorDefault, 0, &OFNSObjectArrayCallbacks);
    CFArrayAppendValue((CFMutableArrayRef)_children, child);
}

- (void) removeChild: (id) child;
{
    OBPRECONDITION([child isKindOfClass: [NSString class]] || [child isKindOfClass: [OFXMLElement class]]);

    [_children removeObjectIdenticalTo: child];
}

- (void) removeChildAtIndex: (unsigned int) childIndex;
{
    [_children removeObjectAtIndex: childIndex];
}

- (void)removeAllChildren;
{
    [_children removeAllObjects];
}

- (void)setChildren:(NSArray *)children;
{
#ifdef OMNI_ASSERTIONS_ON
    {
        unsigned int childIndex = [children count];
        while (childIndex--)
            OBPRECONDITION([[children objectAtIndex:childIndex] respondsToSelector:@selector(appendXML:withParentWhiteSpaceBehavior:document:level:error:)]);
    }
#endif

    if (_children)
        [_children setArray:children];
    else if ([children count] > 0)
        _children = [[NSMutableArray alloc] initWithArray:children];
}

- (void)sortChildrenUsingFunction:(NSComparisonResult (*)(id, id, void *))comparator context:(void *)context;
{
    [_children sortUsingFunction:comparator context:context];
}

// TODO: Really need a common superclass for OFXMLElement and OFXMLFrozenElement
- (OFXMLElement *)firstChildNamed:(NSString *)childName;
{
    unsigned int childIndex, childCount = [_children count];
    for (childIndex = 0; childIndex < childCount; childIndex++) {
        id child = [_children objectAtIndex:childIndex];
        if ([child respondsToSelector:@selector(name)]) {
            NSString *name = [child name];
            if ([name isEqualToString:childName])
                return child;
        }
    }

    return nil;
}

// Does a bunch of -firstChildNamed: calls with each name split by '/'.  This isn't XPath, just a convenience.  Don't put a '/' at the beginning since there is always relative to the receiver.
- (OFXMLElement *)firstChildAtPath:(NSString *)path;
{
    OBPRECONDITION([path hasPrefix:@"/"] == NO);
    
    // Not terribly efficient.  Might use CF later to avoid autoreleases at least.
    NSArray *pathComponents = [path componentsSeparatedByString:@"/"];
    unsigned int pathIndex, pathCount = [pathComponents count];

    OFXMLElement *currentElement = self;
    for (pathIndex = 0; pathIndex < pathCount; pathIndex++)
        currentElement = [currentElement firstChildNamed:[pathComponents objectAtIndex:pathIndex]];
    return currentElement;
}


- (OFXMLElement *)firstChildWithAttribute:(NSString *)attributeName value:(NSString *)value;
{
    OBPRECONDITION(attributeName);
    OBPRECONDITION(value); // Can't look for unset attributes for now.
    
    unsigned int childIndex, childCount = [_children count];
    for (childIndex = 0; childIndex < childCount; childIndex++) {
        id child = [_children objectAtIndex:childIndex];
        if ([child respondsToSelector:@selector(attributeNamed:)]) {
            NSString *attributeValue = [child attributeNamed:attributeName];
            if ([value isEqualToString:attributeValue])
                return child;
        }
    }
    
    return nil;
}

- (NSArray *) attributeNames;
{
    return _attributeOrder;
}

- (NSString *) attributeNamed: (NSString *) name;
{
    return [_attributes objectForKey: name];
}

- (void) setAttribute: (NSString *) name string: (NSString *) value;
{
    if (!_attributeOrder) {
        OBASSERT(!_attributes);
        _attributeOrder = [[NSMutableArray alloc] init];
        _attributes = [[NSMutableDictionary alloc] init];
    }

    OBASSERT([_attributeOrder count] == [_attributes count]);

    if (value) {
        if (![_attributes objectForKey:name])
            [_attributeOrder addObject:name];
        id copy = [value copy];
        [_attributes setObject:copy forKey:name];
        [copy release];
    } else {
        [_attributeOrder removeObject:name];
        [_attributes removeObjectForKey:name];
    }
}

- (void) setAttribute: (NSString *) name value: (id) value;
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

- (OFXMLElement *)appendElement:(NSString *)elementName containingString:(NSString *)contents;
{
    OFXMLElement *child = [[OFXMLElement alloc] initWithName: elementName];
    if (![NSString isEmptyString: contents])
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

- (OFXMLElement *)appendElement:(NSString *)elementName containingDate:(NSDate *)date;
{
    return [self appendElement:elementName containingString:[date xmlString]];
}

- (void) removeAttributeNamed: (NSString *) name;
{
    if ([_attributes objectForKey: name]) {
        [_attributeOrder removeObject: name];
        [_attributes removeObjectForKey: name];
    }
}

- (void)sortAttributesUsingFunction:(NSComparisonResult (*)(id, id, void *))comparator context:(void *)context;
{
    [_attributeOrder sortUsingFunction:comparator context:context];
}

- (void)sortAttributesUsingSelector:(SEL)comparator;
{
    [_attributeOrder sortUsingSelector:comparator];
}

- (void)setIgnoreUnlessReferenced:(BOOL)flag;
{
    _flags.ignoreUnlessReferenced = (flag != NO);
}

- (BOOL)ignoreUnlessReferenced;
{
    return (_flags.ignoreUnlessReferenced != 0);
}

- (void)markAsReferenced;
{
    _flags.markedAsReferenced = 1;
}

- (BOOL)shouldIgnore;
{
    if (_flags.ignoreUnlessReferenced)
        return !_flags.markedAsReferenced;
    return NO;
}

- (void)applyFunction:(OFXMLElementApplier)applier context:(void *)context;
{
    // We are an element
    applier(self, context);
    
    unsigned int childIndex, childCount = [_children count];
    for (childIndex = 0; childIndex < childCount; childIndex++) {
	id child = [_children objectAtIndex:childIndex];
	if ([child respondsToSelector:_cmd])
	    [(OFXMLElement *)child applyFunction:applier context:context];
    }
}

- (NSData *)xmlDataAsFragment:(NSError **)outError; // Mostly useful for debugging since this assumes no whitespace is important
{
    OFXMLWhitespaceBehavior *whitespace = [[OFXMLWhitespaceBehavior alloc] init];
    [whitespace setBehavior:OFXMLWhitespaceBehaviorTypeIgnore forElementName:[self name]];
    
    NSError *error = nil;
    OFXMLDocument *doc = [[OFXMLDocument alloc] initWithRootElement:self dtdSystemID:NULL dtdPublicID:nil whitespaceBehavior:whitespace stringEncoding:kCFStringEncodingUTF8 error:&error];
    if (!doc)
        OBASSERT_NOT_REACHED("We always pass the same input parameters, so this should never error out");
    
    [whitespace release];
    
    NSData *xml = [doc xmlDataAsFragment:outError];
    [doc release];
    
    return xml;
}

//
// NSObject (OFXMLWriting)
//
- (BOOL)appendXML:(struct _OFXMLBuffer *)xml withParentWhiteSpaceBehavior:(OFXMLWhitespaceBehaviorType)parentBehavior document:(OFXMLDocument *)doc level:(unsigned int)level error:(NSError **)outError;
{
    OFXMLWhitespaceBehaviorType whitespaceBehavior;

    if (_flags.ignoreUnlessReferenced && !_flags.markedAsReferenced)
        return YES; // trivial success

    whitespaceBehavior = [[doc whitespaceBehavior] behaviorForElementName: _name];
    if (whitespaceBehavior == OFXMLWhitespaceBehaviorTypeAuto)
        whitespaceBehavior = parentBehavior;

    OFXMLBufferAppendUTF8CString(xml, "<");
    OFXMLBufferAppendString(xml, (CFStringRef)_name);
    
    if (_attributeOrder) {
        // Quote the attribute values
        CFStringEncoding encoding = [doc stringEncoding];
        unsigned int attributeIndex, attributeCount = [_attributeOrder count];
        for (attributeIndex = 0; attributeIndex < attributeCount; attributeIndex++) {
            NSString *name = [_attributeOrder objectAtIndex:attributeIndex];
            NSString *value = [_attributes objectForKey:name];

            OBASSERT(value); // If we write out <element key>, libxml will hate us. This shouldn't happen, but it has once.
            if (!value)
                continue;
            
            OFXMLBufferAppendUTF8CString(xml, " ");
            OFXMLBufferAppendString(xml, (CFStringRef)name);
            
            if (value) {
                OFXMLBufferAppendUTF8CString(xml, "=\"");
                NSString *quotedString = OFXMLCreateStringWithEntityReferencesInCFEncoding(value, OFXMLBasicEntityMask, nil, encoding);
                OFXMLBufferAppendString(xml, (CFStringRef)quotedString);
                [quotedString release];
                OFXMLBufferAppendUTF8CString(xml, "\"");
            }
        }
    }

    BOOL hasWrittenChild = NO;
    BOOL doIntenting = NO;
    
    // See if any of our children are non-ignored and use this for isEmpty instead of the plain count
    unsigned int childIndex, childCount = [_children count];
    for (childIndex = 0; childIndex < childCount; childIndex++) {
        id child = [_children objectAtIndex:childIndex];
        if ([child respondsToSelector:@selector(shouldIgnore)] && [child shouldIgnore])
            continue;
        
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
    }

    if (doIntenting) {
        OFXMLBufferAppendUTF8CString(xml, "\n");
        OFXMLBufferAppendSpaces(xml, 2*level);
    }
    
    if (hasWrittenChild) {
        OFXMLBufferAppendUTF8CString(xml, "</");
        OFXMLBufferAppendString(xml, (CFStringRef)_name);
        OFXMLBufferAppendUTF8CString(xml, ">");
    } else
        OFXMLBufferAppendUTF8CString(xml, "/>");
    
    return YES;
}

- (BOOL)xmlRepresentationCanContainChildren;
{
    return YES;
}

- (NSObject *)copyFrozenElement;
{
    // Frozen elements don't have any support for marking referenced
    return [[OFXMLFrozenElement alloc] initWithName:_name children:_children attributes:_attributes attributeOrder:_attributeOrder];
}

#pragma mark -
#pragma mark Comparison

- (BOOL)isEqual:(id)otherObject;
{
    // This means we don't consider OFXMLElement, OFXMLFrozenElement or OFXMLUnparsedElement the same, even if they would produce the same output.  Not sure if this is a bug; let's catch this case here to see if it ever hits.
    OBPRECONDITION([otherObject isKindOfClass:[OFXMLElement class]]);
    if (![otherObject isKindOfClass:[OFXMLElement class]])
        return NO;
    
    OFXMLElement *otherElement = otherObject;
    
    if (OFNOTEQUAL(_name, otherElement->_name))
        return NO;
    
    // Allow nil to be equal to empty
    
    if ([_attributeOrder count] != 0 || [otherElement->_attributeOrder count] != 0) {
        // For now, at least, we'll consider elements with the same attributes, but in different orders, to be non-equal.
        if (OFNOTEQUAL(_attributeOrder, otherElement->_attributeOrder))
            return NO;
    }
    if ([_attributes count] != 0 || [otherElement->_attributes count] != 0) {
        if (OFNOTEQUAL(_attributes, otherElement->_attributes))
            return NO;
    }
    
    if ([_children count] != 0 || [otherElement->_children count] != 0) {
        if (OFNOTEQUAL(_children, otherElement->_children))
            return NO;
    }
    
    // Ignoring the flags
    return YES;
}

#pragma mark -
#pragma mark Debugging

- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *debugDictionary;

    debugDictionary = [super debugDictionary];
    [debugDictionary setObject: _name forKey: @"_name"];
    if (_children)
        [debugDictionary setObject: _children forKey: @"_children"];
    if (_attributes) {
        [debugDictionary setObject: _attributeOrder forKey: @"_attributeOrder"];
        [debugDictionary setObject: _attributes forKey: @"_attributes"];
    }

    return debugDictionary;
}

- (NSString *)debugDescription;
{
    NSError *error = nil;
    NSData *data = [self xmlDataAsFragment:&error];
    if (!data) {
        NSLog(@"Error converting element to data: %@", [error toPropertyList]);
        return [error description];
    }
    
    return [NSString stringWithData:data encoding:NSUTF8StringEncoding];
}

@end


@implementation NSObject (OFXMLWritingPartial)

#if 0 // NOT implementing this since our precondition in -appendChild: is easier this way.
- (BOOL)appendXML:(struct _OFXMLBuffer *)xml withParentWhiteSpaceBehavior:(OFXMLWhitespaceBehaviorType)parentBehavior document:(OFXMLDocument *)doc level:(unsigned int)level error:(NSError **)outError;
{
    OBRejectUnusedImplementation(isa, _cmd);
}
#endif

- (BOOL)xmlRepresentationCanContainChildren;
{
    return NO;
}

- (NSObject *)copyFrozenElement;
{
    return [self retain];
}
@end
