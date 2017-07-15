// Copyright 2016-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFTestCase.h"

#import <OmniFoundation/OFXMLParser.h>
#import <OmniFoundation/OFXMLParser-Internal.h>
#import <OmniFoundation/OFXMLQName.h>

RCS_ID("$Id$");

@interface OFXMLParserUnparsedElementTests : OFTestCase <OFXMLParserTarget>
@end

@implementation OFXMLParserUnparsedElementTests
{
    NSString *_unparsedElementIdentifier;
    NSString *_unparsedElementData;
}

- (void)setUp;
{
    [super setUp];

    _unparsedElementIdentifier = nil;
    _unparsedElementData = nil;
}

- (void)tearDown;
{
    _unparsedElementIdentifier = nil;
    _unparsedElementData = nil;
    
    [super tearDown];
}

- (void)testUnparsedElementWithIdentifier;
{
    NSString *xmlString = @"<root><foo id=\"a1\">blah blah<x>blah</x></foo></root>";

    NSError *error = nil;
    OFXMLParser *parser = [[OFXMLParser alloc] initWithWhitespaceBehavior:[OFXMLWhitespaceBehavior ignoreWhitespaceBehavior] defaultWhitespaceBehavior:OFXMLWhitespaceBehaviorTypeIgnore target:self];
    OBShouldNotError([parser parseData:[xmlString dataUsingEncoding:NSUTF8StringEncoding] error:&error]);

    XCTAssertEqualObjects(_unparsedElementIdentifier, @"a1");
    XCTAssertEqualObjects(_unparsedElementData, [@"<foo id=\"a1\">blah blah<x>blah</x></foo>" dataUsingEncoding:NSUTF8StringEncoding]);
}

- (void)testLargeUnparsedElementWithIdentifier;
{
    [self _testUnparsedElementWithIdentifierOfLength:370000 withMaximumParserChunkSize:256];
}

- (void)testVeryLargeUnparsedElementWithIdentifierUsingDefaultParserChunkSize;
{
    NSUInteger maximumParserChunkSize = [OFXMLParser defaultMaximumParseChunkSize];
    NSUInteger elementLength = maximumParserChunkSize * 4;
    
    [self _testUnparsedElementWithIdentifierOfLength:elementLength withMaximumParserChunkSize:maximumParserChunkSize];
}

- (void)_testUnparsedElementWithIdentifierOfLength:(NSUInteger)unparsedElementLength withMaximumParserChunkSize:(NSUInteger)maximumParserChuckSize;
{
    NSString *filler1 = [[NSUUID UUID] UUIDString];
    NSMutableString *filler2 = [NSMutableString string];
    
    // `unparsedElementLength` is the approximate length of the unparsed element
    
    while (filler2.length < unparsedElementLength) {
        [filler2 appendString:[[NSUUID UUID] UUIDString]];
        [filler2 appendString:@"/"];
    }
    
    NSString *unparsedElementString = [NSString stringWithFormat:@"<foo id=\"a1\">%@<x>%@</x></foo>", filler1, filler2];
    NSData *unparsedElementData = [unparsedElementString dataUsingEncoding:NSUTF8StringEncoding];
    
    NSString *xmlString = [NSString stringWithFormat:@"<root>%@</root>", unparsedElementString];
    
    NSError *error = nil;
    OFXMLParser *parser = [[OFXMLParser alloc] initWithWhitespaceBehavior:[OFXMLWhitespaceBehavior ignoreWhitespaceBehavior] defaultWhitespaceBehavior:OFXMLWhitespaceBehaviorTypeIgnore target:self];
    parser.maximumParseChunkSize = maximumParserChuckSize; // Ensure that the unparsed data spans several parser chunks
    OBShouldNotError([parser parseData:[xmlString dataUsingEncoding:NSUTF8StringEncoding] error:&error]);
    
    XCTAssertEqualObjects(_unparsedElementIdentifier, @"a1");
    XCTAssertEqualObjects(_unparsedElementData, unparsedElementData);
}

- (OFXMLParserElementBehavior)parser:(OFXMLParser *)parser behaviorForElementWithQName:(OFXMLQName *)name multipleAttributeGenerator:(id <OFXMLParserMultipleAttributeGenerator>)multipleAttributeGenerator singleAttributeGenerator:(id <OFXMLParserSingleAttributeGenerator>)singleAttributeGenerator;
{
    if ([name.name isEqual:@"foo"]) {
        return OFXMLParserElementBehaviorUnparsed;
    }
    return OFXMLParserElementBehaviorParse;
}

- (void)parser:(OFXMLParser *)parser endUnparsedElementWithQName:(OFXMLQName *)qname identifier:(NSString *)identifier contents:(NSData *)contents;
{
    _unparsedElementIdentifier = [identifier copy];
    _unparsedElementData = [contents copy];
}

@end
