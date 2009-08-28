// Copyright 2003-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#define STEnableDeprecatedAssertionMacros
#import "OFTestCase.h"

#import <OmniFoundation/OFXMLCursor.h>
#import <OmniFoundation/OFXMLDocument.h>
#import <OmniFoundation/OFXMLElement.h>
#import <OmniFoundation/OFXMLWhitespaceBehavior.h>

#import <OmniBase/OmniBase.h>

RCS_ID("$Id$");


@interface OFXMLCursorTests : OFTestCase
{
    OFXMLDocument *doc;
}

@end

@implementation OFXMLCursorTests

- (id) initWithInvocation:(NSInvocation *) anInvocation
{
    if (!(self = [super initWithInvocation: anInvocation]))
        return nil;
    
    // Just use a little fragment
    NSString *xmlString =
    @"<root id='0'>\n"
    @"  <child id='1'/>\n"
    @"  <child id='2'>text</child>\n"
    @"  <child id='3'><grandchild/></child>\n"
    @"</root>\n";

    NSData *xmlData = [xmlString dataUsingEncoding: NSUTF8StringEncoding];

    // Ignore all whitespace
    OFXMLWhitespaceBehavior *whitespace = [[OFXMLWhitespaceBehavior alloc] init];
    [whitespace setBehavior: OFXMLWhitespaceBehaviorTypeIgnore forElementName: @"root"];

    NSError *error = nil;
    doc = [[OFXMLDocument alloc] initWithData:xmlData whitespaceBehavior:whitespace error:&error];
    [whitespace release];

    //NSLog(@"doc = %@", doc);
    return self;
}

- (void) dealloc;
{
    [doc release];
    [super dealloc];
}

- (void) testBasicCursor;
{
    OFXMLCursor *cursor = [doc cursor];
    should(cursor != nil);
    should([cursor currentElement] == [doc rootElement]);
    should([cursor currentChild] == nil);
    shouldBeEqual([cursor name], @"root");
    shouldBeEqual([cursor attributeNamed: @"id"], @"0");
    
    shouldBeEqual([cursor currentPath], @"/root/");  // trailing slash since we haven't started enumerating children
}

- (void) testEnumerateChildren;
{
    id child;
    unsigned int childIndex, childCount;
    
    OFXMLCursor *cursor = [doc cursor];

    childCount = [[[doc rootElement] children] count];
    for (childIndex = 0; childIndex < childCount; childIndex++) {
        child = [cursor nextChild];
        should(child != nil);
        shouldBeEqual(child, [[[doc rootElement] children] objectAtIndex: childIndex]);
    }

    // After all the valid children, should return nil
    child = [cursor nextChild];
    shouldBeEqual(child, nil);

    // Should keep returning nil
    child = [cursor nextChild];
    shouldBeEqual(child, nil);

    child = [cursor nextChild];
    shouldBeEqual(child, nil);
}

- (void) testOpenCloseElement;
{
    id child1;
    
    OFXMLCursor *cursor = [doc cursor];

    child1 = [cursor nextChild];

    [cursor openElement]; // child 1
    {
        shouldBeEqual([cursor currentElement], child1);
        shouldBeEqual([cursor currentChild], nil);
        shouldBeEqual([cursor name], @"child");
        shouldBeEqual([cursor attributeNamed: @"id"], @"1");
        
        // child 1 has no children
        shouldBeEqual([cursor nextChild], nil);
    }
    [cursor closeElement];

    // Should be back to the first child now
    shouldBeEqual([cursor currentChild], child1);
    shouldBeEqual([cursor name], @"root");
    shouldBeEqual([cursor attributeNamed: @"id"], @"0");

    // Next child
    id child2 = [cursor nextChild];
    [cursor openElement];
    {
        shouldBeEqual([cursor currentElement], child2);
        shouldBeEqual([cursor currentChild], nil);
        shouldBeEqual([cursor name], @"child");
        shouldBeEqual([cursor attributeNamed: @"id"], @"2");

        // child 2 has one child that is text
        shouldBeEqual([cursor nextChild], @"text");
        shouldBeEqual([cursor nextChild], nil);
    }
    [cursor closeElement];

    // Final child
    id child3 = [cursor nextChild];
    [cursor openElement];
    {
        shouldBeEqual([cursor currentElement], child3);
        shouldBeEqual([cursor currentChild], nil);
        shouldBeEqual([cursor name], @"child");
        shouldBeEqual([cursor attributeNamed: @"id"], @"3");

        // child 3 has one child that is an element
        id grandchild = [cursor nextChild];
        shouldBeEqual([grandchild name], @"grandchild");
        [cursor openElement];
        {
            shouldBeEqual([cursor currentElement], grandchild);

            // no children of the grandchild
            shouldBeEqual([cursor currentChild], nil);
            shouldBeEqual([cursor nextChild], nil);
        }
        [cursor closeElement];
    }
    [cursor closeElement];
}

@end
