// Copyright 2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OFTestCase.h"

#import <OmniFoundation/OFXMLParser.h>
#import <OmniFoundation/OFXMLQName.h>

RCS_ID("$Id$");

@interface OFXMLParserTests : OFTestCase <OFXMLParserTarget>
@end

@implementation OFXMLParserTests
{
    OFXMLQName *_rootElementQName;
    NSArray <OFXMLQName *> *_rootElementAttributeQNames;

    NSMutableDictionary <NSString *, OFXMLQName *> *_elementQNameByPlainName;
}

- (void)setUp;
{
    [super setUp];

    _elementQNameByPlainName = [[NSMutableDictionary alloc] init];
    _rootElementAttributeQNames = nil;
}

- (void)tearDown;
{
    _elementQNameByPlainName = nil;
    _rootElementAttributeQNames = nil;

    [super tearDown];
}

- (void)testNamespaces;
{
    NSString *xmlString = @"<root xmlns=\"http://root.example.com\" xmlns:a=\"http://a.example.com\" xmlns:b=\"http://b.example.com\"><a:a/><b:b/><c/></root>";

    NSError *error = nil;
    OFXMLParser *parser = [[OFXMLParser alloc] initWithWhitespaceBehavior:[OFXMLWhitespaceBehavior ignoreWhitespaceBehavior] defaultWhitespaceBehavior:OFXMLWhitespaceBehaviorTypeIgnore target:self];
    OBShouldNotError([parser parseData:[xmlString dataUsingEncoding:NSUTF8StringEncoding] error:&error]);

    OFXMLQName *qName;

    XCTAssertEqualObjects(_rootElementQName.name, @"root");
    XCTAssertEqualObjects(_rootElementQName.namespace, @"http://root.example.com");

    XCTAssertEqual([_rootElementAttributeQNames count], 3UL);

    // The attibutes that define namespaces are themselves part of the xml namespace
    qName = _rootElementAttributeQNames[0];
    XCTAssertEqualObjects(qName.name, @"");
    XCTAssertEqualObjects(qName.namespace, @"http://www.w3.org/2000/xmlns/");

    qName = _rootElementAttributeQNames[1];
    XCTAssertEqualObjects(qName.name, @"a");
    XCTAssertEqualObjects(qName.namespace, @"http://www.w3.org/2000/xmlns/");

    qName = _rootElementAttributeQNames[2];
    XCTAssertEqualObjects(qName.name, @"b");
    XCTAssertEqualObjects(qName.namespace, @"http://www.w3.org/2000/xmlns/");


    // The element names once used, should have the specific namespaces.
    qName = _elementQNameByPlainName[@"root"];
    XCTAssertEqualObjects(qName.name, @"root");
    XCTAssertEqualObjects(qName.namespace, @"http://root.example.com");

    qName = _elementQNameByPlainName[@"a"];
    XCTAssertEqualObjects(qName.name, @"a");
    XCTAssertEqualObjects(qName.namespace, @"http://a.example.com");

    qName = _elementQNameByPlainName[@"b"];
    XCTAssertEqualObjects(qName.name, @"b");
    XCTAssertEqualObjects(qName.namespace, @"http://b.example.com");

    qName = _elementQNameByPlainName[@"c"];
    XCTAssertEqualObjects(qName.name, @"c");
    XCTAssertEqualObjects(qName.namespace, @"http://root.example.com");

}

- (void)testProgressReporting;
{
    // Build an XML string long enough to actually produce progress states between 0% and 100%
    NSMutableString *xmlString = [@"<root xmlns=\"http://root.example.com\">" mutableCopy];
    for (NSUInteger i = 0; i < 250000; i++) {
        [xmlString appendFormat:@"<integerelement>%tu</integerelement>", i];
    }
    [xmlString appendString:@"</root>"];
    
    NSData *xmlData = [xmlString dataUsingEncoding:NSUTF8StringEncoding];
    
    OFXMLParser *parser = [[OFXMLParser alloc] initWithWhitespaceBehavior:[OFXMLWhitespaceBehavior ignoreWhitespaceBehavior] defaultWhitespaceBehavior:OFXMLWhitespaceBehaviorTypeIgnore target:self];
    OBASSERT([xmlData length] > parser.maximumParseChunkSize); // OFXMLParser creates 4MB chunks, so let's make sure there's more than one such chunk

    XCTestExpectation *intermediateExpectation = [self keyValueObservingExpectationForObject:parser.progress keyPath:@"completedUnitCount" expectedValue:@(4 * 1024 * 1024)];
    XCTestExpectation *completedExpectation = [self keyValueObservingExpectationForObject:parser.progress keyPath:@"completedUnitCount" expectedValue:@([xmlData length])];
    
    NSError *error = nil;
    OBShouldNotError([parser parseData:xmlData error:&error]);
    
    // Progress should already be done, so give no additional time
    [self waitForExpectationsWithTimeout:0 handler:^(NSError * _Nullable expectationError) {
        XCTAssertNil(expectationError);
    }];
    
    // Hold on to the expectations at least this long
    [intermediateExpectation self];
    [completedExpectation self];
}

// MARK:- OFXMLParserTarget

- (void)parser:(OFXMLParser *)parser startElementWithQName:(OFXMLQName *)qname multipleAttributeGenerator:(id <OFXMLParserMultipleAttributeGenerator>)multipleAttributeGenerator singleAttributeGenerator:(id <OFXMLParserSingleAttributeGenerator>)singleAttributeGenerator;
{
    if ([qname.name isEqual:@"root"]) {
        _rootElementQName = [qname copy];

        if (multipleAttributeGenerator) {
            [multipleAttributeGenerator generateAttributesWithQNames:^(NSMutableArray<OFXMLQName *> *qnames, NSMutableArray<NSString *> *values) {
                _rootElementAttributeQNames = qnames;
            }];
        } else if (singleAttributeGenerator) {
            [singleAttributeGenerator generateAttributeWithQName:^(OFXMLQName *attributeQName, NSString *attributeValue) {
                _rootElementAttributeQNames = @[attributeQName];
            }];
        } else {
            _rootElementAttributeQNames = nil;
        }
    }

    _elementQNameByPlainName[qname.name] = qname;
}

@end
