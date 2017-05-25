// Copyright 2003-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFXMLElementParser.h>

#import <OmniFoundation/OFXMLElement.h>
#import <OmniFoundation/OFXMLQName.h>
#import <OmniFoundation/OFXMLParser.h>
#import <OmniFoundation/OFXMLComment.h>
#import <OmniFoundation/OFXMLUnparsedElement.h>

RCS_ID("$Id$");

NS_ASSUME_NONNULL_BEGIN

@implementation OFXMLElementParser
{
    __weak id <OFXMLElementParserDelegate> _weak_delegate;

    OFXMLElement *_rootElement; // of our parse, not necessarily the whole document.
    NSMutableArray *_elementStack; // Maybe just use a counter
}

- init;
{
    if (!(self = [super init])) {
        return nil;
    }

    _elementStack = [[NSMutableArray alloc] init];

    return self;
}

- (void)dealloc {

    [_rootElement release];
    [_elementStack release];
    [super dealloc];
}

@synthesize delegate = _weak_delegate;

- (OFXMLElement *)topElement;
{
    OFXMLElement *element = OB_CHECKED_CAST(OFXMLElement, [_elementStack lastObject]);
    return element;
}

- (void)parser:(OFXMLParser *)parser startElementWithQName:(OFXMLQName *)qname multipleAttributeGenerator:(id <OFXMLParserMultipleAttributeGenerator>)multipleAttributeGenerator singleAttributeGenerator:(id <OFXMLParserSingleAttributeGenerator>)singleAttributeGenerator;
{
    OBPRECONDITION(qname);

    OFXMLElement *element;

    if (multipleAttributeGenerator) {
        __block NSMutableArray *attributeOrder = nil;
        __block NSMutableDictionary *attributeDictionary = nil;

        [multipleAttributeGenerator generateAttributesWithPlainNames:^(NSMutableArray<NSString *> *names, NSMutableDictionary<NSString *,NSString *> *values) {
            // We are *not* copying these since OFXMLParser specifically yields mutable instances for its target to take over.
            attributeOrder = [names retain];
            attributeDictionary = [values retain];
        }];

        element = [[OFXMLElement alloc] initWithName:qname.name attributeOrder:attributeOrder attributes:attributeDictionary];
        [attributeOrder release];
        [attributeDictionary release];
    } else if (singleAttributeGenerator) {
        __block NSString *attributeName = nil;
        __block NSString *attributeValue = nil;

        [singleAttributeGenerator generateAttributeWithPlainName:^(NSString *name, NSString *value) {
            attributeName = [name copy];
            attributeValue = [value copy];
        }];

        element = [[OFXMLElement alloc] initWithName:qname.name attributeName:attributeName attributeValue:attributeValue];
        [attributeName release];
        [attributeValue release];
    } else {
        element = [[OFXMLElement alloc] initWithName:qname.name];
    }


    if (!_rootElement) {
        _rootElement = [element retain];
        OBASSERT([_elementStack count] == 0);
        [_elementStack addObject: _rootElement];
    } else {
        OBASSERT([_elementStack count] != 0);
        [[_elementStack lastObject] appendChild: element];
        [_elementStack addObject: element];
    }
    [element release];
}

// Should only be called if the whitespace behavior indicates we wanted it and we are inside the root element.
- (void)parser:(OFXMLParser *)parser addWhitespace:(NSString *)whitespace;
{
    OBPRECONDITION(_rootElement);

    // Note that we are not calling -_addString: here since that does string merging but whitespace should (I think) only be reported in cases where we don't want it merged or it can't be merged.  This needs more investigation and test cases, etc.
    [self.topElement appendChild:whitespace];
}

// If the last child of the top element is a string, replace it with the concatenation of the two strings.
// TODO: Later we should have OFXMLString be an array of strings that is lazily concatenated to avoid slow degenerate cases (and then replace the last string with a OFXMLString with the two elements).  Actually, it might be better to just stick in an NSMutableArray of strings and then clean it up when the element is finished.
- (void)parser:(OFXMLParser *)parser addString:(NSString *)string;
{
    OFXMLElement *top = self.topElement;
    NSArray *children = top.children;
    NSUInteger count = [children count];

    if (count) {
        id lastChild = [children lastObject];
        if ([lastChild isKindOfClass:[NSString class]]) {
            NSString *newString = [[NSString alloc] initWithFormat: @"%@%@", lastChild, string];
            [top removeChildAtIndex:count - 1];
            [top appendChild:newString];
            [newString release];
            return;
        }
    }

    [top appendChild:string];
}

- (void)parser:(OFXMLParser *)parser addComment:(NSString *)string;
{
    OFXMLElement *top = self.topElement;
    OFXMLComment *comment = [[OFXMLComment alloc] initWithString:string];
    [top appendChild:comment];
    [comment release];
}

- (void)parser:(OFXMLParser *)parser endElementWithQName:(OFXMLQName *)qname;
{
    OBPRECONDITION([_elementStack count] != 0);

    OFXMLElement *element = [_elementStack lastObject];
    OBASSERT([element.name isEqual:qname.name]);

    BOOL isRootElement = (_rootElement == element);
    [_elementStack removeLastObject];

    OBASSERT(isRootElement == ([_elementStack count] == 0));

    if (isRootElement) {
        // Prepare for re-use.
        [element retain];

        [_rootElement release];
        _rootElement = nil;

        [_elementStack removeAllObjects];

        [_weak_delegate elementParser:self parser:parser parsedElement:element];
        [element release];
    }
}

- (OFXMLParserElementBehavior)parser:(OFXMLParser *)parser behaviorForElementWithQName:(OFXMLQName *)name multipleAttributeGenerator:(id <OFXMLParserMultipleAttributeGenerator>)multipleAttributeGenerator singleAttributeGenerator:(id <OFXMLParserSingleAttributeGenerator>)singleAttributeGenerator;
{
    id <OFXMLElementParserDelegate> delegate = _weak_delegate;
    if (!delegate) {
        // ...  though we have no way to report our results, so maybe we should return 'skip'.
        return OFXMLParserElementBehaviorParse;
    }

    return [delegate elementParser:self behaviorForElementWithQName:name multipleAttributeGenerator:multipleAttributeGenerator singleAttributeGenerator:singleAttributeGenerator];
}

- (void)parser:(OFXMLParser *)parser endUnparsedElementWithQName:(OFXMLQName *)qname identifier:(NSString *)identifier contents:(NSData *)contents;
{
    OBPRECONDITION(_rootElement);

    OFXMLUnparsedElement *element = [[OFXMLUnparsedElement alloc] initWithQName:qname identifier:identifier data:contents];
    [self.topElement appendChild:element];
    [element release];
}

@end

NS_ASSUME_NONNULL_END
