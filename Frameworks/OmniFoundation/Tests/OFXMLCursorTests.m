// Copyright 2003-2008, 2010, 2013-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

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

    //NSLog(@"doc = %@", doc);
    return self;
}


- (void) testBasicCursor;
{
    OFXMLCursor *cursor = [doc cursor];
    XCTAssertTrue(cursor != nil);
    XCTAssertTrue([cursor currentElement] == [doc rootElement]);
    XCTAssertTrue([cursor currentChild] == nil);
    XCTAssertEqualObjects([cursor name], @"root");
    XCTAssertEqualObjects([cursor attributeNamed: @"id"], @"0");
    
    XCTAssertEqualObjects([cursor currentPath], @"/root/");  // trailing slash since we haven't started enumerating children
}

- (void) testEnumerateChildren;
{
    id child;
    NSUInteger childIndex, childCount;
    
    OFXMLCursor *cursor = [doc cursor];

    childCount = [[[doc rootElement] children] count];
    for (childIndex = 0; childIndex < childCount; childIndex++) {
        child = [cursor nextChild];
        XCTAssertTrue(child != nil);
        XCTAssertEqual(child, [[[doc rootElement] children] objectAtIndex: childIndex]);
    }

    // After all the valid children, should return nil
    child = [cursor nextChild];
    XCTAssertNil(child);

    // Should keep returning nil
    child = [cursor nextChild];
    XCTAssertNil(child);

    child = [cursor nextChild];
    XCTAssertNil(child);
}

- (void) testOpenCloseElement;
{
    id child1;
    
    OFXMLCursor *cursor = [doc cursor];

    child1 = [cursor nextChild];

    [cursor openElement]; // child 1
    {
        XCTAssertEqual([cursor currentElement], child1);
        XCTAssertNil([cursor currentChild]);
        XCTAssertEqualObjects([cursor name], @"child");
        XCTAssertEqualObjects([cursor attributeNamed: @"id"], @"1");
        
        // child 1 has no children
        XCTAssertNil([cursor nextChild]);
    }
    [cursor closeElement];

    // Should be back to the first child now
    XCTAssertEqual([cursor currentChild], child1);
    XCTAssertEqualObjects([cursor name], @"root");
    XCTAssertEqualObjects([cursor attributeNamed: @"id"], @"0");

    // Next child
    id child2 = [cursor nextChild];
    [cursor openElement];
    {
        XCTAssertEqual([cursor currentElement], child2);
        XCTAssertNil([cursor currentChild]);
        XCTAssertEqualObjects([cursor name], @"child");
        XCTAssertEqualObjects([cursor attributeNamed: @"id"], @"2");

        // child 2 has one child that is text
        XCTAssertEqualObjects([cursor nextChild], @"text");
        XCTAssertNil([cursor nextChild]);
    }
    [cursor closeElement];

    // Final child
    id child3 = [cursor nextChild];
    [cursor openElement];
    {
        XCTAssertEqual([cursor currentElement], child3);
        XCTAssertNil([cursor currentChild]);
        XCTAssertEqualObjects([cursor name], @"child");
        XCTAssertEqualObjects([cursor attributeNamed: @"id"], @"3");

        // child 3 has one child that is an element
        id grandchild = [cursor nextChild];
        XCTAssertEqualObjects([grandchild name], @"grandchild");
        [cursor openElement];
        {
            XCTAssertEqual([cursor currentElement], grandchild);

            // no children of the grandchild
            XCTAssertNil([cursor currentChild]);
            XCTAssertNil([cursor nextChild]);
        }
        [cursor closeElement];
    }
    [cursor closeElement];
}

@end
