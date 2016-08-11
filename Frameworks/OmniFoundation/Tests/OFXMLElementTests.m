// Copyright 2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFTestCase.h"

#import <OmniFoundation/OFXMLDocument.h>
#import <OmniFoundation/OFXMLElement.h>
#import <OmniFoundation/OFXMLWhitespaceBehavior.h>

RCS_ID("$Id$");

/*
 Many of these tests are white-box/code coverage to make sure we test the various inline storage cases in OFXMLElement.
 */

@interface OFXMLElementTests : OFTestCase
@end

@implementation OFXMLElementTests
{
    OFXMLElement *_root;
}

- (void)setUp;
{
    [super setUp];

    _root = [[OFXMLElement alloc] initWithName:@"root"];
}

- (void)tearDown;
{
    _root = nil;
    [super tearDown];
}

- (void)testNotEqualWithDifferentNames;
{
    OFXMLElement *child1 = [[OFXMLElement alloc] initWithName:@"child1"];
    OFXMLElement *child2 = [[OFXMLElement alloc] initWithName:@"child2"];

    OBAssertNotEqualObjects(child1, child2);
}

- (void)testEqualWhenEmpty;
{
    OFXMLElement *child1 = [[OFXMLElement alloc] initWithName:@"child"];
    OFXMLElement *child2 = [[OFXMLElement alloc] initWithName:@"child"];

    OBAssertEqualObjects(child1, child2);
}

- (void)testEqualWithSingleChild;
{
    OFXMLElement *child1 = [[OFXMLElement alloc] initWithName:@"child"];
    [child1 appendElement:@"a" containingString:@""];

    OFXMLElement *child2 = [[OFXMLElement alloc] initWithName:@"child"];
    [child2 appendElement:@"a" containingString:@""];

    OBAssertEqualObjects(child1, child2);
}

- (void)testNotEqualWithSingleChild;
{
    OFXMLElement *child1 = [[OFXMLElement alloc] initWithName:@"child"];
    [child1 appendElement:@"a" containingString:@""];

    OFXMLElement *child2 = [[OFXMLElement alloc] initWithName:@"child"];
    [child2 appendElement:@"b" containingString:@""];

    OBAssertNotEqualObjects(child1, child2);
}

- (void)testNotEqualWithMultipleChildren;
{
    OFXMLElement *child1 = [[OFXMLElement alloc] initWithName:@"child"];
    [child1 appendElement:@"a" containingString:@""];
    [child1 appendElement:@"b" containingString:@""];

    OFXMLElement *child2 = [[OFXMLElement alloc] initWithName:@"child"];
    [child2 appendElement:@"b" containingString:@""];
    [child2 appendElement:@"a" containingString:@""];

    OBAssertNotEqualObjects(child1, child2);
}

- (void)testNotEqualWithDifferntChildCounts;
{
    OFXMLElement *child1 = [[OFXMLElement alloc] initWithName:@"child"];
    [child1 appendElement:@"a" containingString:@""];

    OFXMLElement *child2 = [[OFXMLElement alloc] initWithName:@"child"];
    [child2 appendElement:@"a" containingString:@""];
    [child2 appendElement:@"b" containingString:@""];

    OBAssertNotEqualObjects(child1, child2);
}

- (void)testEqualWithMultipleChildren;
{
    OFXMLElement *child1 = [[OFXMLElement alloc] initWithName:@"child"];
    [child1 appendElement:@"a" containingString:@""];
    [child1 appendElement:@"b" containingString:@""];

    OFXMLElement *child2 = [[OFXMLElement alloc] initWithName:@"child"];
    [child2 appendElement:@"a" containingString:@""];
    [child2 appendElement:@"b" containingString:@""];

    OBAssertEqualObjects(child1, child2);
}

- (void)testApplyBlockWhenEmpty;
{
    NSMutableArray *seen = [NSMutableArray array];
    [_root applyBlock:^(OFXMLElement * _Nonnull element) {
        [seen addObject:element];
    }];

    OBAssertEqualObjects(seen, @[_root]);
}

- (void)testApplyBlockWithSingle;
{
    OFXMLElement *child = [_root appendElement:@"child" containingString:@""];

    NSMutableArray *seen = [NSMutableArray array];
    [_root applyBlock:^(OFXMLElement * _Nonnull element) {
        [seen addObject:element];
    }];

    OBAssertEqualObjects(seen, (@[_root, child]));
}

- (void)testApplyBlockWithMultiple;
{
    OFXMLElement *child1 = [_root appendElement:@"child1" containingString:@""];
    OFXMLElement *child2 = [_root appendElement:@"child2" containingString:@""];

    NSMutableArray *seen = [NSMutableArray array];
    [_root applyBlock:^(OFXMLElement * _Nonnull element) {
        [seen addObject:element];
    }];

    OBAssertEqualObjects(seen, (@[_root, child1, child2]));
}

- (void)testApplyBlockWithMultipleLevels;
{
    OFXMLElement *child1 = [_root appendElement:@"child1" containingString:@""];
    OFXMLElement *grand1A = [child1 appendElement:@"grand1A" containingString:@""];
    OFXMLElement *grand1B = [child1 appendElement:@"grand1B" containingString:@""];

    OFXMLElement *child2 = [_root appendElement:@"child1" containingString:@""];
    OFXMLElement *grand2A = [child2 appendElement:@"grand2A" containingString:@""];
    OFXMLElement * grand2B = [child2 appendElement:@"grand2B" containingString:@""];

    NSMutableArray *seen = [NSMutableArray array];
    [_root applyBlock:^(OFXMLElement * _Nonnull element) {
        [seen addObject:element];
    }];

    OBAssertEqualObjects(seen, (@[_root, child1, grand1A, grand1B, child2, grand2A, grand2B]));
}

- (void)testFirstChildWithNameWhenEmpty;
{
    XCTAssertNil([_root firstChildNamed:@"child"]);
}

- (void)testFirstChildWithNameWithSingle;
{
    OFXMLElement *child = [_root appendElement:@"child" containingString:@""];
    XCTAssertEqual([_root firstChildNamed:@"child"], child);
    XCTAssertNil([_root firstChildNamed:@"x"]);
}

- (void)testFirstChildWithNameWithMultiple;
{
    OFXMLElement *child1 = [_root appendElement:@"child1" containingString:@""];
    OFXMLElement *child2 = [_root appendElement:@"child2" containingString:@""];

    XCTAssertEqual([_root firstChildNamed:@"child1"], child1);
    XCTAssertEqual([_root firstChildNamed:@"child2"], child2);
    XCTAssertNil([_root firstChildNamed:@"x"]);
}

- (void)testFirstChildAtPath;
{
    OFXMLElement *a = [_root appendElement:@"a" containingString:@""];
    OFXMLElement *b = [a appendElement:@"b" containingString:@""];
    [a appendElement:@"b" containingString:@""];

    XCTAssertEqual([_root firstChildAtPath:@"a/b"], b);
}

- (void)testFirstChildWithAttributeWhenEmpty;
{
    XCTAssertNil([_root firstChildWithAttribute:@"child" value:@"x"]);
}

- (void)testFirstChildWithAttributeWithSingle;
{
    OFXMLElement *child = [_root appendElement:@"child" containingString:@""];
    [child setAttribute:@"attr" string:@"x"];

    XCTAssertEqual([_root firstChildWithAttribute:@"attr" value:@"x"], child);
    XCTAssertNil([_root firstChildWithAttribute:@"attr" value:@"y"]);
}

- (void)testFirstChildWithAttributeWithMultiple;
{
    OFXMLElement *child1 = [_root appendElement:@"child" containingString:@""];
    [child1 setAttribute:@"attr" string:@"x"];

    OFXMLElement *child2 = [_root appendElement:@"child" containingString:@""];
    [child2 setAttribute:@"attr" string:@"y"];

    XCTAssertEqual([_root firstChildWithAttribute:@"attr" value:@"x"], child1);
    XCTAssertEqual([_root firstChildWithAttribute:@"attr" value:@"y"], child2);
    XCTAssertNil([_root firstChildWithAttribute:@"attr" value:@"z"]);
}

- (void)testFirstChildWithNameWithMultipleHavingSameName;
{
    OFXMLElement *child1 = [_root appendElement:@"child" containingString:@""];
    [_root appendElement:@"child" containingString:@""];

    XCTAssertEqual([_root firstChildNamed:@"child"], child1);
    XCTAssertNil([_root firstChildNamed:@"x"]);
}

- (void)testRemoveChildAtIndexWhenEmpty;
{
    // TJW: Change from non-inline storage -- didn't throw
    XCTAssertThrows([_root removeChildAtIndex:0]);
}

- (void)testRemoveChildAtIndexWithSingleChild;
{
    [_root appendElement:@"child" containingString:@""];
    XCTAssertThrows([_root removeChildAtIndex:1]);

    [_root removeChildAtIndex:0];
    XCTAssertEqual(_root.childrenCount, 0UL);
    XCTAssertNil(_root.lastChild);
}

- (void)testRemoveChildAtIndexWithMultipleChildren;
{
    [_root appendElement:@"child1" containingString:@""];
    OFXMLElement *child2 = [_root appendElement:@"child2" containingString:@""];

    XCTAssertThrows([_root removeChildAtIndex:2]);

    [_root removeChildAtIndex:0];
    XCTAssertEqual(_root.childrenCount, 1UL);
    XCTAssertEqual(_root.lastChild, child2);
}

- (void)testSetChildrenWhenEmpty;
{
    OFXMLElement *child1 = [[OFXMLElement alloc] initWithName:@"child1"];
    OFXMLElement *child2 = [[OFXMLElement alloc] initWithName:@"child2"];

    [_root setChildren:@[child1, child2]];
    XCTAssertEqual(_root.childrenCount, 2UL);
    XCTAssertEqual([_root childAtIndex:0], child1);
    XCTAssertEqual([_root childAtIndex:1], child2);
}

- (void)testSetChildrenWithSingleChild;
{
    [_root appendElement:@"a" containingString:@""];

    OFXMLElement *child1 = [[OFXMLElement alloc] initWithName:@"child1"];
    OFXMLElement *child2 = [[OFXMLElement alloc] initWithName:@"child2"];

    [_root setChildren:@[child1, child2]];
    XCTAssertEqual(_root.childrenCount, 2UL);
    XCTAssertEqual([_root childAtIndex:0], child1);
    XCTAssertEqual([_root childAtIndex:1], child2);
}

- (void)testSetChildrenWithMultipleChildren;
{
    [_root appendElement:@"a" containingString:@""];
    [_root appendElement:@"b" containingString:@""];

    OFXMLElement *child1 = [[OFXMLElement alloc] initWithName:@"child1"];
    OFXMLElement *child2 = [[OFXMLElement alloc] initWithName:@"child2"];

    [_root setChildren:@[child1, child2]];
    XCTAssertEqual(_root.childrenCount, 2UL);
    XCTAssertEqual([_root childAtIndex:0], child1);
    XCTAssertEqual([_root childAtIndex:1], child2);
}

- (void)testSetChildrenToSingleWithSingle;
{
    [_root appendElement:@"a" containingString:@""];

    OFXMLElement *child = [[OFXMLElement alloc] initWithName:@"child1"];

    [_root setChildren:@[child]];
    XCTAssertEqual(_root.childrenCount, 1UL);
    XCTAssertEqual([_root childAtIndex:0], child);
}

- (void)testSetChildrenToEmptyWithSingle;
{
    [_root appendElement:@"a" containingString:@""];

    [_root setChildren:@[]];
    XCTAssertEqual(_root.childrenCount, 0UL);
    XCTAssertNil(_root.lastChild);
}

- (void)testChildrenEmpty;
{
    XCTAssertEqual(_root.childrenCount, 0UL);
    XCTAssertNil(_root.lastChild);

    // TJW: Change from non-inline storage -- didn't throw, just asserted
    XCTAssertThrows([_root childAtIndex:0]);

    // TJW: Change from non-inline storage -- returned zero here.
    XCTAssertEqual([_root indexOfChildIdenticalTo:_root], NSNotFound);

    // Doing this last since we know it can upgrade the internal format of the element.
    XCTAssertNil(_root.children);
}

- (void)testChildrenSingle;
{
    OFXMLElement *child = [_root appendElement:@"child" containingString:@""];

    XCTAssertEqual(_root.childrenCount, 1UL);
    XCTAssertEqual(_root.lastChild, child);
    XCTAssertEqual([_root childAtIndex:0], child);
    XCTAssertThrows([_root childAtIndex:1]);
    XCTAssertEqual([_root indexOfChildIdenticalTo:_root], NSNotFound);
    XCTAssertEqual([_root indexOfChildIdenticalTo:child], 0UL);

    // Doing this last since we know it can upgrade the internal format of the element.
    OBAssertEqualObjects(_root.children, @[child]);
}

- (void)testChildrenMultiple;
{
    OFXMLElement *child1 = [_root appendElement:@"child" containingString:@"1"];
    OFXMLElement *child2 = [_root appendElement:@"child" containingString:@"1"];

    XCTAssertEqual(_root.childrenCount, 2UL);
    XCTAssertEqual(_root.lastChild, child2);
    XCTAssertEqual([_root childAtIndex:0], child1);
    XCTAssertEqual([_root childAtIndex:1], child2);
    XCTAssertThrows([_root childAtIndex:2]);
    XCTAssertEqual([_root indexOfChildIdenticalTo:_root], NSNotFound);
    XCTAssertEqual([_root indexOfChildIdenticalTo:child1], 0UL);
    XCTAssertEqual([_root indexOfChildIdenticalTo:child2], 1UL);

    // Doing this last since we know it can upgrade the internal format of the element.
    OBAssertEqualObjects(_root.children, (@[child1, child2]));
}

- (void)testDeepCopyEmpty;
{
    OFXMLElement *copy = [_root deepCopy];

    OBAssertEqualObjects(copy.name, @"root");
    XCTAssertNil(copy.attributeNames);
    XCTAssertEqual(copy.childrenCount, 0UL);
    XCTAssertNil(copy.children);
    XCTAssertNil(copy.lastChild);
}

- (void)testDeepCopySingleChild;
{
    OFXMLElement *child = [_root appendElement:@"child" containingString:@""];
    OFXMLElement *copy = [_root deepCopy];

    OBAssertEqualObjects(copy.name, @"root");
    XCTAssertNil(copy.attributeNames);
    XCTAssertEqual(copy.childrenCount, 1UL);

    OFXMLElement *childCopy = copy.lastChild;
    XCTAssertNotNil(childCopy);
    XCTAssertNotEqual(childCopy, child);
    OBAssertEqualObjects(childCopy.name, child.name);

    // Doing this last since we know it can upgrade the internal format of the element.
    OBAssertEqualObjects(copy.children, @[child]);
}

- (void)testDeepCopyMultipleChildren;
{
    OFXMLElement *child1 = [_root appendElement:@"child1" containingString:@"1"];
    OFXMLElement *child2 = [_root appendElement:@"child2" containingString:@"2"];
    OFXMLElement *copy = [_root deepCopy];

    OBAssertEqualObjects(copy.name, @"root");
    XCTAssertNil(copy.attributeNames);
    XCTAssertEqual(copy.childrenCount, 2UL);

    OFXMLElement *child1Copy = [copy childAtIndex:0];
    OFXMLElement *child2Copy = [copy childAtIndex:1];

    XCTAssertNotEqual(child1Copy, child1);
    OBAssertEqualObjects(child1Copy.name, child1.name);

    XCTAssertNotEqual(child2Copy, child2);
    OBAssertEqualObjects(child2Copy.name, child2.name);

    XCTAssertEqual(copy.lastChild, child2Copy);

    // Doing this last since we know it can upgrade the internal format of the element.
    OBAssertEqualObjects(copy.children, (@[child1, child2]));
}

- (void)testAttributeLookupWhenEmpty;
{
    XCTAssertNil([_root attributeNamed:@"attr"]);
}

- (void)testAttributeLookupWithSingle;
{
    [_root setAttribute:@"attr" string:@"x"];
    OBAssertEqualObjects([_root attributeNamed:@"attr"], @"x");
    XCTAssertNil([_root attributeNamed:@"qqq"]);
}

- (void)testAttributeLookupWithMultiple;
{
    [_root setAttribute:@"attr1" string:@"x"];
    [_root setAttribute:@"attr2" string:@"y"];
    OBAssertEqualObjects([_root attributeNamed:@"attr1"], @"x");
    OBAssertEqualObjects([_root attributeNamed:@"attr2"], @"y");
    XCTAssertNil([_root attributeNamed:@"qqq"]);
}

// This is very white-box... checking that temporarily updating an element to multiple attributes and back down still results in proper equality checking (since going _back_ to a single attribute doesn't downgrade the storage format).
- (void)testCompareWithSingleVsMultipleAttributeStorage;
{
    OFXMLElement *a = [[OFXMLElement alloc] initWithName:@"root"];
    [a setAttribute:@"attr1" string:@"x"];
    [a setAttribute:@"attr2" string:@"y"];
    [a setAttribute:@"attr2" string:nil];

    OFXMLElement *b = [[OFXMLElement alloc] initWithName:@"root"];
    [b setAttribute:@"attr1" string:@"x"];

    OBAssertEqualObjects(a, b);
}

- (void)testCompareWithDifferentAttributeCounts;
{
    OFXMLElement *a = [[OFXMLElement alloc] initWithName:@"root"];
    [a setAttribute:@"attr1" string:@"x"];
    [a setAttribute:@"attr2" string:@"y"];

    OFXMLElement *b = [[OFXMLElement alloc] initWithName:@"root"];
    [b setAttribute:@"attr1" string:@"x"];

    OBAssertNotEqualObjects(a, b);
}

- (void)testDeepCopyWithSingleAttribute;
{
    [_root setAttribute:@"attr" string:@"x"];

    OFXMLElement *copy = [_root deepCopy];
    OBAssertEqualObjects(_root, copy);

    [copy setAttribute:@"attr" string:@"y"];
    XCTAssert(![_root isEqual:copy]);
}

- (void)testDeepCopyWithMultipleAttributes;
{
    [_root setAttribute:@"attr1" string:@"x"];
    [_root setAttribute:@"attr2" string:@"y"];

    OFXMLElement *copy = [_root deepCopy];
    XCTAssert([_root isEqual:copy]);

    [copy setAttribute:@"attr1" string:@"z"];
    XCTAssert(![_root isEqual:copy]);
}

- (void)testInsertChildWhenEmpty;
{
    OFXMLElement *child = [[OFXMLElement alloc] initWithName:@"child"];

    // TJW: Change from non-inline storage -- didn't throw; actually created the item and added it twice!
    XCTAssertThrows([_root insertChild:child atIndex:1]);

    [_root insertChild:child atIndex:0];

    XCTAssertEqual(_root.childrenCount, 1UL);
    XCTAssertEqual([_root childAtIndex:0], child);
    XCTAssertEqual(_root.lastChild, child);
}

- (void)testInsertChildAtBeginngingWithSingleChild;
{
    OFXMLElement *child1 = [_root appendElement:@"child1" containingString:@""];

    OFXMLElement *child2 = [[OFXMLElement alloc] initWithName:@"child2"];

    XCTAssertThrows([_root insertChild:child2 atIndex:2]);
    [_root insertChild:child2 atIndex:0];

    XCTAssertEqual(_root.childrenCount, 2UL);
    XCTAssertEqual([_root childAtIndex:0], child2);
    XCTAssertEqual([_root childAtIndex:1], child1);
    XCTAssertEqual(_root.lastChild, child1);
    OBAssertEqualObjects(_root.children, (@[child2, child1]));
}

- (void)testInsertChildAtEndWithSingleChild;
{
    OFXMLElement *child1 = [_root appendElement:@"child1" containingString:@""];
    OFXMLElement *child2 = [[OFXMLElement alloc] initWithName:@"child2"];

    XCTAssertThrows([_root insertChild:child2 atIndex:2]);
    [_root insertChild:child2 atIndex:1];

    XCTAssertEqual(_root.childrenCount, 2UL);
    XCTAssertEqual([_root childAtIndex:0], child1);
    XCTAssertEqual([_root childAtIndex:1], child2);
    XCTAssertEqual(_root.lastChild, child2);
    OBAssertEqualObjects(_root.children, (@[child1, child2]));
}

- (void)testRemoveChildWhileEmpty;
{
    OFXMLElement *child = [[OFXMLElement alloc] initWithName:@"child"];

    [_root removeChild:child];

    XCTAssertEqual(_root.childrenCount, 0UL);
    XCTAssertNil(_root.lastChild);
}

- (void)testRemoveChildWithSingleChild;
{
    OFXMLElement *child1 = [_root appendElement:@"child1" containingString:@""];
    OFXMLElement *child2 = [[OFXMLElement alloc] initWithName:@"child2"];

    [_root removeChild:child2]; // does nothing

    XCTAssertEqual(_root.childrenCount, 1UL);
    XCTAssertEqual(_root.lastChild, child1);

    [_root removeChild:child1];

    XCTAssertEqual(_root.childrenCount, 0UL);
    XCTAssertNil(_root.lastChild);
}

- (void)testRemoveChildWithMultipleChildren;
{
    OFXMLElement *child1 = [_root appendElement:@"child1" containingString:@""];
    OFXMLElement *child2 = [_root appendElement:@"child2" containingString:@""];

    [_root removeChild:child2];

    XCTAssertEqual(_root.childrenCount, 1UL);
    XCTAssertEqual(_root.lastChild, child1);

    [_root removeChild:child1];

    XCTAssertEqual(_root.childrenCount, 0UL);
    XCTAssertNil(_root.lastChild);
}

- (void)testRemoveAllChildrenWhenEmpty;
{
    [_root removeAllChildren];
    XCTAssertEqual(_root.childrenCount, 0UL);
    XCTAssertNil(_root.lastChild);
}

- (void)testRemoveAllChildrenWithSingleChild;
{
    [_root appendElement:@"child" containingString:@""];
    [_root removeAllChildren];
    XCTAssertEqual(_root.childrenCount, 0UL);
    XCTAssertNil(_root.lastChild);
}

- (void)testRemoveAllChildrenWithMultipleChildren;
{
    [_root appendElement:@"child1" containingString:@""];
    [_root appendElement:@"child2" containingString:@""];
    [_root removeAllChildren];
    XCTAssertEqual(_root.childrenCount, 0UL);
    XCTAssertNil(_root.lastChild);
}

@end
