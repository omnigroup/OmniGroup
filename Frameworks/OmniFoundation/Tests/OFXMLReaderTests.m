// Copyright 2009-2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFTestCase.h"

#import <OmniFoundation/OFXMLReader.h>
#import <OmniFoundation/OFXMLQName.h>
#import <OmniFoundation/OFErrors.h>
#import <OmniBase/NSError-OBExtensions.h>
#import <OmniBase/rcsid.h>

RCS_ID("$Id$")

@interface OFXMLReaderTests : OFTestCase
@end

@implementation OFXMLReaderTests

- (void)testSkippingEmptyElement;
{
    NSError *error = nil;
    NSString *xml = @"<root><empty1/><empty2/></root>";
    
    OFXMLReader *reader = [[OFXMLReader alloc] initWithData:[xml dataUsingEncoding:NSUTF8StringEncoding] error:&error];
    OBShouldNotError(reader != nil);
    
    OFXMLQName *name = nil;
    XCTAssertEqualObjects([reader elementQName].name, @"root");
    
    OBShouldNotError([reader openElement:&error]);
    
    OBShouldNotError([reader findNextElement:&name error:&error]);
    XCTAssertEqualObjects(name.name, @"empty1");
    
    OBShouldNotError([reader skipCurrentElement:&error]);
    XCTAssertEqualObjects([reader elementQName].name, @"empty2");
    
    OBShouldNotError([reader findNextElement:&name error:&error]);
    XCTAssertEqualObjects(name.name, @"empty2");
}

- (void)testCloseElementSkippingEmptyElement;
{
    NSError *error = nil;
    NSString *xml = @"<root><interior><empty1/><empty2/></interior><follow/></root>";
    
    OFXMLReader *reader = [[OFXMLReader alloc] initWithData:[xml dataUsingEncoding:NSUTF8StringEncoding] error:&error];
    OBShouldNotError(reader != nil);
    
    OFXMLQName *name = nil;
    XCTAssertEqualObjects([reader elementQName].name, @"root");
    
    OBShouldNotError([reader openElement:&error]);
    
    OBShouldNotError([reader findNextElement:&name error:&error]);
    XCTAssertEqualObjects(name.name, @"interior");
    
    OBShouldNotError([reader openElement:&error]);

    OBShouldNotError([reader findNextElement:&name error:&error]);
    XCTAssertEqualObjects(name.name, @"empty1");
    
    OBShouldNotError([reader closeElement:&error]);
    
    OBShouldNotError([reader findNextElement:&name error:&error]);
    XCTAssertEqualObjects(name.name, @"follow");
}

- (void)testCloseElementSkippingMultipleEmptyElement;
{
    NSError *error = nil;
    NSString *xml = @"<root><interior><empty1/><empty2/></interior><follow/></root>";
    
    OFXMLReader *reader = [[OFXMLReader alloc] initWithData:[xml dataUsingEncoding:NSUTF8StringEncoding] error:&error];
    OBShouldNotError(reader != nil);
    
    OFXMLQName *name = nil;
    XCTAssertEqualObjects([reader elementQName].name, @"root");
    
    OBShouldNotError([reader openElement:&error]);
    
    OBShouldNotError([reader findNextElement:&name error:&error]);
    XCTAssertEqualObjects(name.name, @"interior");
    
    OBShouldNotError([reader openElement:&error]);
    
    OBShouldNotError([reader closeElement:&error]);
    
    OBShouldNotError([reader findNextElement:&name error:&error]);
    XCTAssertEqualObjects(name.name, @"follow");
}

- (void)testOpenEmptyElement;
{
    NSError *error = nil;
    NSString *xml = @"<root><empty1/><empty2/></root>";
    
    OFXMLReader *reader = [[OFXMLReader alloc] initWithData:[xml dataUsingEncoding:NSUTF8StringEncoding] error:&error];
    OBShouldNotError(reader != nil);
    
    OFXMLQName *name = nil;
    XCTAssertEqualObjects([reader elementQName].name, @"root");
    
    OBShouldNotError([reader openElement:&error]);
    
    OBShouldNotError([reader findNextElement:&name error:&error]);
    XCTAssertEqualObjects(name.name, @"empty1");
    
    OBShouldNotError([reader openElement:&error]);
    OBShouldNotError([reader closeElement:&error]);

    OBShouldNotError([reader findNextElement:&name error:&error]);
    XCTAssertEqualObjects(name.name, @"empty2");
}

- (void)testCopyString;
{
    NSError *error = nil;
    NSString *xml = @"<root>some text</root>";
    
    OFXMLReader *reader = [[OFXMLReader alloc] initWithData:[xml dataUsingEncoding:NSUTF8StringEncoding] error:&error];
    OBShouldNotError(reader != nil);
    
    OBShouldNotError([reader openElement:&error]);
    
    NSString *str = nil;
    BOOL endedElement = NO;
    OBShouldNotError([reader copyString:&str endingElement:&endedElement error:&error]);
    
    XCTAssertEqualObjects(str, @"some text");
    XCTAssertTrue(endedElement);
    
}

- (void)testCopyStringWithCDATA;
{
    NSError *error = nil;
    NSString *xml = @"<root><![CDATA[some]]><![CDATA[text]]></root>";
    
    OFXMLReader *reader = [[OFXMLReader alloc] initWithData:[xml dataUsingEncoding:NSUTF8StringEncoding] error:&error];
    OBShouldNotError(reader != nil);
    
    OBShouldNotError([reader openElement:&error]);
    
    NSString *str = nil;
    BOOL endedElement = NO;
    OBShouldNotError([reader copyString:&str endingElement:&endedElement error:&error]);
    
    XCTAssertEqualObjects(str, @"sometext");
    XCTAssertTrue(endedElement);
    
}

- (void)testCopyStringWithEmbeddedElements;
{
    NSError *error = nil;
    NSString *xml = @"<root>a<empty1/>b<foo>c</foo></root>";
    
    OFXMLReader *reader = [[OFXMLReader alloc] initWithData:[xml dataUsingEncoding:NSUTF8StringEncoding] error:&error];
    OBShouldNotError(reader != nil);
    
    OBShouldNotError([reader openElement:&error]);
    
    NSString *str = nil;
    BOOL endedElement = NO;
    OBShouldNotError([reader copyString:&str endingElement:&endedElement error:&error]);
    
    XCTAssertEqualObjects(str, @"a");
    XCTAssertFalse(endedElement);
    
}

- (void)testCopyStringToEndWithEmbeddedElements;
{
    NSError *error = nil;
    NSString *xml = @"<root>a<empty1/>b<foo>c</foo></root>";

    OFXMLReader *reader = [[OFXMLReader alloc] initWithData:[xml dataUsingEncoding:NSUTF8StringEncoding] error:&error];
    OBShouldNotError(reader != nil);
    
    NSString *str = nil;
    OBShouldNotError([reader copyStringContentsToEndOfElement:&str error:&error]);
    
    XCTAssertEqualObjects(str, @"abc");

}

- (void)testCopyStringToEndFromMiddleOfElement;
{
    NSError *error = nil;
    NSString *xml = @"<root>a<empty/>b</root>";
    
    OFXMLReader *reader = [[OFXMLReader alloc] initWithData:[xml dataUsingEncoding:NSUTF8StringEncoding] error:&error];
    OBShouldNotError(reader != nil);
    
    OBShouldNotError([reader openElement:&error]); // open <root>
    
    OFXMLQName *nextQName = nil;
    OBShouldNotError([reader findNextElement:&nextQName error:&error]); // find <empty/>
    
    OBShouldNotError([reader skipCurrentElement:&error]); // skip <empty/>
    
    NSString *str = nil;
    OBShouldNotError([reader copyStringContentsToEndOfElement:&str error:&error]);
    
    XCTAssertEqualObjects(str, @"b"); // only string contents after <empty/>
    
}

static void _testReadBoolContents(OFXMLReaderTests *self, SEL _cmd, NSString *inner, BOOL defaultValue, BOOL expectedValue)
{
    NSError *error = nil;
    NSString *xml = [NSString stringWithFormat:@"<root>%@<foo/></root>", inner];
    
    OFXMLReader *reader;
    OBShouldNotError(reader = [[OFXMLReader alloc] initWithData:[xml dataUsingEncoding:NSUTF8StringEncoding] error:&error]);
    
    OBShouldNotError([reader openElement:&error]);
    
    BOOL value = !expectedValue; // make sure it gets written to.
    
    OBShouldNotError([reader readBoolContentsOfElement:&value defaultValue:defaultValue error:&error]);
    
    XCTAssertEqual(value, expectedValue);
    
    // Should have skipped the bool element.
    OFXMLQName *name = nil;
    OBShouldNotError([reader findNextElement:&name error:&error]);
    XCTAssertEqualObjects(name.name, @"foo");
}

- (void)testReadBoolContents;
{
    // empty nodes should yield default values
    _testReadBoolContents(self, _cmd, @"<bool/>", NO, NO);
    _testReadBoolContents(self, _cmd, @"<bool/>", YES, YES);
    
    // start/end nodes should be the same as empty
    _testReadBoolContents(self, _cmd, @"<bool></bool>", NO, NO);
    _testReadBoolContents(self, _cmd, @"<bool></bool>", YES, YES);

    // nodes with only whitespace should be the same as empty
    _testReadBoolContents(self, _cmd, @"<bool> </bool>", NO, NO);
    _testReadBoolContents(self, _cmd, @"<bool> </bool>", YES, YES);
    
    // explicit true/false strings should give their values.
    _testReadBoolContents(self, _cmd, @"<bool>true</bool>", NO, YES);
    _testReadBoolContents(self, _cmd, @"<bool>true</bool>", YES, YES);
    _testReadBoolContents(self, _cmd, @"<bool>false</bool>", NO, NO);
    _testReadBoolContents(self, _cmd, @"<bool>false</bool>", YES, NO);
    
    // 1/0 are supposed to work too.
    _testReadBoolContents(self, _cmd, @"<bool>1</bool>", NO, YES);
    _testReadBoolContents(self, _cmd, @"<bool>1</bool>", YES, YES);
    _testReadBoolContents(self, _cmd, @"<bool>0</bool>", NO, NO);
    _testReadBoolContents(self, _cmd, @"<bool>0</bool>", YES, NO);
    
    // The leading space makes this not exactly match "true" or "1"
    _testReadBoolContents(self, _cmd, @"<bool> true</bool>", NO, NO);
    _testReadBoolContents(self, _cmd, @"<bool> true</bool>", YES, NO);
    _testReadBoolContents(self, _cmd, @"<bool> 1</bool>", NO, NO);
    _testReadBoolContents(self, _cmd, @"<bool> 1</bool>", YES, NO);
    
    // Empty CDATA should be the same as empty
    _testReadBoolContents(self, _cmd, @"<bool><![CDATA[]]></bool>", NO, NO);
    _testReadBoolContents(self, _cmd, @"<bool><![CDATA[]]></bool>", YES, YES);

    // CDATA with space in it isn't considered whitespace and is directly compared to "true" and "1".  Don't do that, silly person.
    _testReadBoolContents(self, _cmd, @"<bool><![CDATA[ ]]></bool>", NO, NO);
    _testReadBoolContents(self, _cmd, @"<bool><![CDATA[ ]]></bool>", YES, NO);
    
    // More CDATA versions of stuff above
    _testReadBoolContents(self, _cmd, @"<bool><![CDATA[true]]></bool>", NO, YES);
    _testReadBoolContents(self, _cmd, @"<bool><![CDATA[true]]></bool>", YES, YES);
    _testReadBoolContents(self, _cmd, @"<bool><![CDATA[false]]></bool>", NO, NO);
    _testReadBoolContents(self, _cmd, @"<bool><![CDATA[false]]></bool>", YES, NO);
    
    _testReadBoolContents(self, _cmd, @"<bool><![CDATA[1]]></bool>", NO, YES);
    _testReadBoolContents(self, _cmd, @"<bool><![CDATA[1]]></bool>", YES, YES);
    _testReadBoolContents(self, _cmd, @"<bool><![CDATA[0]]></bool>", NO, NO);
    _testReadBoolContents(self, _cmd, @"<bool><![CDATA[0]]></bool>", YES, NO);
}

static void _testReadLongContents(OFXMLReaderTests *self, SEL _cmd, NSString *inner, long defaultValue, long expectedValue)
{
    NSError *error = nil;
    NSString *xml = [NSString stringWithFormat:@"<root>%@<foo/></root>", inner];
    
    OFXMLReader *reader = [[OFXMLReader alloc] initWithData:[xml dataUsingEncoding:NSUTF8StringEncoding] error:&error];
    OBShouldNotError(reader != nil);
    
    OBShouldNotError([reader openElement:&error]);
    
    long value = ~expectedValue; // make sure it gets written to.
    
    OBShouldNotError([reader readLongContentsOfElement:&value defaultValue:defaultValue error:&error]);
    
    XCTAssertEqual(value, expectedValue);
    
    // Should have skipped the long element.
    OFXMLQName *name = nil;
    OBShouldNotError([reader findNextElement:&name error:&error]);
    XCTAssertEqualObjects(name.name, @"foo");
}

- (void)testReadLongContents;
{
    // empty nodes should yield default values
    _testReadLongContents(self, _cmd, @"<long/>", 13, 13);
    _testReadLongContents(self, _cmd, @"<long/>", 13, 13);
    
    // start/end nodes should be the same as empty
    _testReadLongContents(self, _cmd, @"<long></long>", 13, 13);
    _testReadLongContents(self, _cmd, @"<long></long>", 13, 13);
    
    // nodes with only whitespace should be the same as empty
    _testReadLongContents(self, _cmd, @"<long> </long>", 13, 13);
    _testReadLongContents(self, _cmd, @"<long> </long>", 13, 13);
    
    // explicit longs should give their values.
    _testReadLongContents(self, _cmd, @"<long>123</long>", 13, 123);
    _testReadLongContents(self, _cmd, @"<long>0</long>", 13, 0);
    _testReadLongContents(self, _cmd, @"<long>-1</long>", 13, -1);
    
    // leading/trailing whitespace is allowed
    _testReadLongContents(self, _cmd, @"<long> 567</long>", 13, 567);
    _testReadLongContents(self, _cmd, @"<long>678 </long>", 13, 678);

    // Empty CDATA should be the same as empty
    _testReadLongContents(self, _cmd, @"<long><![CDATA[]]></long>", 13, 13);
    _testReadLongContents(self, _cmd, @"<long><![CDATA[]]></long>", 13, 13);
    
    // CDATA with space in it isn't considered whitespace and is directly passed to strtol. Don't do that, silly person.
    _testReadLongContents(self, _cmd, @"<long><![CDATA[ ]]></long>", 13, 0);
    _testReadLongContents(self, _cmd, @"<long><![CDATA[ ]]></long>", 13, 0);
    
    // More CDATA versions of stuff above
    _testReadLongContents(self, _cmd, @"<long><![CDATA[123]]></long>", 13, 123);
    _testReadLongContents(self, _cmd, @"<long><![CDATA[0]]></long>", 13, 0);
    _testReadLongContents(self, _cmd, @"<long><![CDATA[-1]]></long>", 13, -1);
}

- (void)testReadPastEndOfFileWithEmptyRoot;
{
    NSString *xmlString = @"<root/>";

    NSError *error = nil;
    OFXMLReader *reader;
    OBShouldNotError(reader = [[OFXMLReader alloc] initWithData:[xmlString dataUsingEncoding:NSUTF8StringEncoding] error:&error]);

    OFXMLQName *qName = reader.elementQName;
    XCTAssertEqualObjects(qName.name, @"root");

    OBShouldNotError([reader openElement:NULL]);
    OBShouldNotError([reader closeElement:NULL]);

    BOOL success = [reader findNextElement:NULL error:&error];
    XCTAssertFalse(success);
    XCTAssertTrue([error hasUnderlyingErrorDomain:OFErrorDomain code:OFXMLReaderEndOfFile]);
}

- (void)testReadPastEndOfFileWithNonEmptyRoot;
{
    NSString *xmlString = @"<root><a/></root>";

    NSError *error = nil;
    OFXMLReader *reader;
    OBShouldNotError(reader = [[OFXMLReader alloc] initWithData:[xmlString dataUsingEncoding:NSUTF8StringEncoding] error:&error]);

    OFXMLQName *qName = reader.elementQName;
    XCTAssertEqualObjects(qName.name, @"root");

    OBShouldNotError([reader openElement:NULL]);
    OBShouldNotError([reader closeElement:NULL]);

    XCTAssertFalse([reader findNextElement:NULL error:&error]);
    XCTAssertTrue([error hasUnderlyingErrorDomain:OFErrorDomain code:OFXMLReaderEndOfFile]);
}

- (void)testNamespaces;
{
    NSString *xmlString = @"<root xmlns=\"http://root.example.com\" xmlns:a=\"http://a.example.com\" xmlns:b=\"http://b.example.com\"><a:a/><b:b/><c/></root>";

    NSError *error = nil;
    OFXMLReader *reader;
    OBShouldNotError(reader = [[OFXMLReader alloc] initWithData:[xmlString dataUsingEncoding:NSUTF8StringEncoding] error:&error]);

    OFXMLQName *qName;

    qName = reader.elementQName;
    XCTAssertEqualObjects(qName.name, @"root");
    XCTAssertEqualObjects(qName.namespace, @"http://root.example.com");

    OBShouldNotError([reader openElement:&error]);

    qName = reader.elementQName;
    XCTAssertEqualObjects(qName.name, @"a");
    XCTAssertEqualObjects(qName.namespace, @"http://a.example.com");

    OBShouldNotError([reader skipCurrentElement:&error]);

    qName = reader.elementQName;
    XCTAssertEqualObjects(qName.name, @"b");
    XCTAssertEqualObjects(qName.namespace, @"http://b.example.com");

    OBShouldNotError([reader skipCurrentElement:&error]);

    qName = reader.elementQName;
    XCTAssertEqualObjects(qName.name, @"c");
    XCTAssertEqualObjects(qName.namespace, @"http://root.example.com");
}

@end
