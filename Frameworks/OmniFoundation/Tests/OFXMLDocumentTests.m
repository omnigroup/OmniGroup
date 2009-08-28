// Copyright 2003-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#define STEnableDeprecatedAssertionMacros
#import "OFTestCase.h"

#import <OmniFoundation/OFStringDecoder.h>
#import <OmniFoundation/OFXMLDocument.h>
#import <OmniFoundation/OFXMLElement.h>
#import <OmniFoundation/OFXMLWhitespaceBehavior.h>
#import <OmniFoundation/NSData-OFExtensions.h>
#import <OmniFoundation/NSFileManager-OFExtensions.h>
#import <OmniFoundation/NSObject-OFExtensions.h>
#import <OmniFoundation/NSString-OFExtensions.h>

#import <OmniBase/OmniBase.h>

RCS_ID("$Id$");

static NSString * const DTDName = @"root-element";
static CFURLRef dtdURL = NULL;

static OFXMLWhitespaceBehavior *IgnoreAllWhitespace(void)
{
    static OFXMLWhitespaceBehavior *whitespace = nil;
    
    if (!whitespace) {
        whitespace = [[OFXMLWhitespaceBehavior alloc] init];
        [whitespace setBehavior:OFXMLWhitespaceBehaviorTypeIgnore forElementName:DTDName];
    }
    
    return whitespace;
}

#define SAVE_AND_COMPARE(expectedString) \
do { \
    NSError *error = nil; \
    NSString *pattern = [NSString stringWithFormat:@"%@-%@.xml", NSStringFromClass(isa), NSStringFromSelector(_cmd)]; \
    NSString *fileName = [[NSFileManager defaultManager] scratchFilenameNamed:pattern error:&error]; \
    should(fileName != nil); \
    if (!fileName) { \
        NSLog(@"Unable to create scratch file '%@' - %@", pattern, error); \
        break; \
    } \
    BOOL writeToFileSucceeded = [doc writeToFile:fileName error:&error]; \
    OBShouldNotError(writeToFileSucceeded); \
    \
    NSData *data = [[NSData alloc] initWithContentsOfFile:fileName]; \
    should(data != nil); \
    \
    OBShouldNotError([[NSFileManager defaultManager] removeItemAtPath:fileName error:&error]); \
    \
    NSString *string = (NSString *)CFStringCreateFromExternalRepresentation(kCFAllocatorDefault, (CFDataRef)data, [doc stringEncoding]); \
    [data release]; \
    \
    STAssertEqualObjects(string, expectedString, @"SAVE_AND_COMPARE"); \
    [string release]; \
} while (0)

@interface OFXMLDocumentTests : OFTestCase
@end

@implementation OFXMLDocumentTests

+ (void) initialize;
{
    [super initialize];
    if (dtdURL)
        return;

    dtdURL = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, (CFStringRef)[DTDName stringByAppendingPathExtension: @"dtd"], kCFURLPOSIXPathStyle, false);
}

- (void)testWriteEmptyDocument;
{
    NSError *error = nil;
    OFXMLDocument *doc = [[OFXMLDocument alloc] initWithRootElementName:DTDName
                                                            dtdSystemID:dtdURL
                                                            dtdPublicID:@"-//omnigroup.com//XML Document Test//EN"
                                                     whitespaceBehavior:IgnoreAllWhitespace()
                                                         stringEncoding:kCFStringEncodingUTF8
                                                                  error:&error];
    OBShouldNotError(doc != nil);
    
    SAVE_AND_COMPARE(@"<?xml version=\"1.0\" encoding=\"utf-8\" standalone=\"no\"?>\n"
                     @"<!DOCTYPE root-element PUBLIC \"-//omnigroup.com//XML Document Test//EN\" \"root-element.dtd\">\n"
                     @"<root-element/>\n");
    
    [doc release];
}

- (void) testWriteDocumentWithOneChild;
{
    NSError *error = nil;
    OFXMLDocument *doc = [[OFXMLDocument alloc] initWithRootElementName:DTDName
                                                            dtdSystemID:dtdURL
                                                            dtdPublicID:@"-//omnigroup.com//XML Document Test//EN"
                                                     whitespaceBehavior:IgnoreAllWhitespace()
                                                         stringEncoding:kCFStringEncodingUTF8
                                                                  error:&error];

    [doc pushElement: @"child"];
    {
        [doc setAttribute: @"name" value: @"value"];
        [doc pushElement: @"grandchild"];
        {
            [doc setAttribute: @"name2" value: @"value2"];
        }
        [doc popElement];
    }
    [doc popElement];

    SAVE_AND_COMPARE(@"<?xml version=\"1.0\" encoding=\"utf-8\" standalone=\"no\"?>\n"
                     @"<!DOCTYPE root-element PUBLIC \"-//omnigroup.com//XML Document Test//EN\" \"root-element.dtd\">\n"
                     @"<root-element>\n"
                     @"  <child name=\"value\">\n"
                     @"    <grandchild name2=\"value2\"/>\n"
                     @"  </child>\n"
                     @"</root-element>\n");

    [doc release];
}

- (void) testWriteSpacePreservation;
{
    OFXMLWhitespaceBehavior *whitespace = [[OFXMLWhitespaceBehavior alloc] init];
    [whitespace setBehavior: OFXMLWhitespaceBehaviorTypeIgnore forElementName: DTDName];
    [whitespace setBehavior: OFXMLWhitespaceBehaviorTypePreserve forElementName: @"p"];

    NSError *error = nil;
    OFXMLDocument *doc = [[OFXMLDocument alloc] initWithRootElementName:DTDName
                                                            dtdSystemID:dtdURL
                                                            dtdPublicID:@"-//omnigroup.com//XML Document Test//EN"
                                                     whitespaceBehavior:whitespace
                                                         stringEncoding:kCFStringEncodingUTF8
                                                                  error:&error];
    [whitespace release];

    [doc pushElement: @"child"];
    {
        [doc setAttribute: @"name" value: @"value"];
        [doc pushElement: @"p"];
        {
            [doc appendString: @"some text "];
            [doc pushElement: @"b"];
            {
                [doc appendString: @"bold"];
            }
            [doc popElement];
        }
        [doc popElement];
    }
    [doc popElement];

    SAVE_AND_COMPARE(@"<?xml version=\"1.0\" encoding=\"utf-8\" standalone=\"no\"?>\n"
                     @"<!DOCTYPE root-element PUBLIC \"-//omnigroup.com//XML Document Test//EN\" \"root-element.dtd\">\n"
                     @"<root-element>\n"
                     @"  <child name=\"value\">\n"
                     @"    <p>some text <b>bold</b></p>\n"
                     @"  </child>\n"
                     @"</root-element>\n");
    
    [doc release];
}

- (void) testReadingFile;
{
    NSString *inputFile = [[self bundle] pathForResource:@"0000-CreateDocument" ofType:@"xmloutline"];
    should(inputFile != nil);

    // Just preserve whitespace exactly was we find it.
    NSError *error = nil;
    OFXMLDocument *doc = [[OFXMLDocument alloc] initWithContentsOfFile:inputFile whitespaceBehavior:nil error:&error];
    should(doc != nil);

    NSData *expectedData = [[NSData alloc] initWithContentsOfFile:inputFile];
    NSString *expectedString = (NSString *)CFStringCreateFromExternalRepresentation(kCFAllocatorDefault, (CFDataRef)expectedData, [doc stringEncoding]);
    [expectedData release];
    
    should(expectedString != nil);
    [expectedString release];
    [doc release];
}

- (void) testEntityWriting_ASCII;
{
    NSString *stringElementName = @"s";
    NSError *error = nil;
    OFXMLDocument *doc = [[[OFXMLDocument alloc] initWithRootElementName:DTDName
                                                             dtdSystemID:dtdURL
                                                             dtdPublicID:@"-//omnigroup.com//XML Document Test//EN"
                                                      whitespaceBehavior:nil
                                                          stringEncoding:kCFStringEncodingASCII
                                                                   error:&error] autorelease];

    NSString *supplementalChararacter1 = [NSString stringWithCharacter:0x12345];
    NSString *supplementalChararacter2 = [NSString stringWithCharacter:0xFEDCB];
    

    // Test writing various entities as CDATA and attributes.
#define ATTR(s) [doc pushElement: stringElementName]; { [doc setAttribute:@"attr" string:s]; [doc appendString:s]; } [doc popElement];
    ATTR(@"&");
    ATTR(@"&amp;");
    ATTR(@"<");
    ATTR(@"&lt;");
    ATTR(@">");
    ATTR(@"&gt;");
    ATTR(@"'");
    ATTR(@"&apos;");
    ATTR(@"\"");
    ATTR(@"&quot;");
    ATTR(supplementalChararacter1);
    ATTR(supplementalChararacter2);
    ATTR(@"a&b");
    ATTR(@"a & b");
#undef ATTR

    NSData *xmlData = [doc xmlDataAsFragment:&error];
    OBShouldNotError(xmlData != nil);
    
    NSString *resultString;
    resultString = [(NSString *)CFStringCreateFromExternalRepresentation(kCFAllocatorDefault, (CFDataRef)xmlData, [doc stringEncoding]) autorelease];

    NSString *expectedOutput =
        @"<root-element>"
        @"<s attr=\"&amp;\">&amp;</s>"
        @"<s attr=\"&amp;amp;\">&amp;amp;</s>"
        @"<s attr=\"&lt;\">&lt;</s>"
        @"<s attr=\"&amp;lt;\">&amp;lt;</s>"
        @"<s attr=\"&gt;\">&gt;</s>"
        @"<s attr=\"&amp;gt;\">&amp;gt;</s>"
        @"<s attr=\"&apos;\">&apos;</s>"
        @"<s attr=\"&amp;apos;\">&amp;apos;</s>"
        @"<s attr=\"&quot;\">&quot;</s>"
        @"<s attr=\"&amp;quot;\">&amp;quot;</s>"
        @"<s attr=\"&#74565;\">&#74565;</s>"
        @"<s attr=\"&#1043915;\">&#1043915;</s>"
        @"<s attr=\"a&amp;b\">a&amp;b</s>"
        @"<s attr=\"a &amp; b\">a &amp; b</s>"
        @"</root-element>";
    shouldBeEqual(resultString, expectedOutput);
}

- (void) testEntityWriting_UTF8;
{
    NSString *stringElementName = @"s";
    NSError *error = nil;
    OFXMLDocument *doc = [[[OFXMLDocument alloc] initWithRootElementName:DTDName
                                                             dtdSystemID:dtdURL
                                                             dtdPublicID:@"-//omnigroup.com//XML Document Test//EN"
                                                      whitespaceBehavior:nil
                                                          stringEncoding:kCFStringEncodingUTF8
                                                                   error:&error] autorelease];

    NSString *supplementalChararacter1 = [NSString stringWithCharacter:0x12345];
    NSString *supplementalChararacter2 = [NSString stringWithCharacter:0xFEDCB];
#define SUPP1_UTF8_LEN 4
    const char supplementalCharacter1UTF8[SUPP1_UTF8_LEN] = { 0xF0, 0x92, 0x8D, 0x85 };
#define SUPP2_UTF8_LEN 4
    const char supplementalCharacter2UTF8[SUPP2_UTF8_LEN] = { 0xF3, 0xBE, 0xB7, 0x8B };

    // Test writing various entities as CDATA and attributes.
#define ATTR(s) [doc pushElement:stringElementName]; { [doc setAttribute:@"attr" string:s]; [doc appendString:s]; } [doc popElement];
    ATTR(@"&");
    ATTR(@"&amp;");
    ATTR(@"<");
    ATTR(@"&lt;");
    ATTR(@">");
    ATTR(@"&gt;");
    ATTR(@"'");
    ATTR(@"&apos;");
    ATTR(@"\"");
    ATTR(@"&quot;");
    ATTR(supplementalChararacter1);
    ATTR(supplementalChararacter2);
    ATTR(@"a&b");
    ATTR(@"a & b");
#undef ATTR

    NSData *xmlData = [doc xmlDataAsFragment:&error];
    OBShouldNotError(xmlData != nil);

    NSString *expectedOutputFormat =
        @"<root-element>"
        @"<s attr=\"&amp;\">&amp;</s>"
        @"<s attr=\"&amp;amp;\">&amp;amp;</s>"
        @"<s attr=\"&lt;\">&lt;</s>"
        @"<s attr=\"&amp;lt;\">&amp;lt;</s>"
        @"<s attr=\"&gt;\">&gt;</s>"
        @"<s attr=\"&amp;gt;\">&amp;gt;</s>"
        @"<s attr=\"&apos;\">&apos;</s>"
        @"<s attr=\"&amp;apos;\">&amp;apos;</s>"
        @"<s attr=\"&quot;\">&quot;</s>"
        @"<s attr=\"&amp;quot;\">&amp;quot;</s>"
        @"<s attr=\"%@\">%@</s>"
        @"<s attr=\"%@\">%@</s>"
        @"<s attr=\"a&amp;b\">a&amp;b</s>"
        @"<s attr=\"a &amp; b\">a &amp; b</s>"
        @"</root-element>";
        
    // Test that the result, as data, is what we expect it to be (this ensures that we're getting the correct UTF8 byte sequence for the supplementary characters)
    NSMutableData *expectedData = [[[expectedOutputFormat dataUsingEncoding:NSASCIIStringEncoding] mutableCopy] autorelease];
    NSData *patternData = [@"%@" dataUsingEncoding:NSASCIIStringEncoding];
    [expectedData replaceBytesInRange:[expectedData rangeOfData:patternData] withBytes:supplementalCharacter1UTF8 length:SUPP1_UTF8_LEN];
    [expectedData replaceBytesInRange:[expectedData rangeOfData:patternData] withBytes:supplementalCharacter1UTF8 length:SUPP1_UTF8_LEN];
    [expectedData replaceBytesInRange:[expectedData rangeOfData:patternData] withBytes:supplementalCharacter2UTF8 length:SUPP2_UTF8_LEN];
    [expectedData replaceBytesInRange:[expectedData rangeOfData:patternData] withBytes:supplementalCharacter2UTF8 length:SUPP2_UTF8_LEN];
    shouldBeEqual(xmlData, expectedData);
    
    
    // Test that the result, converted to a string, is the same as we think it should be
    NSString *resultString, *expectedResultString;
    resultString = [(NSString *)CFStringCreateFromExternalRepresentation(kCFAllocatorDefault, (CFDataRef)xmlData, [doc stringEncoding]) autorelease];
    expectedResultString = [NSString stringWithFormat:expectedOutputFormat,
        supplementalChararacter1, supplementalChararacter1,
        supplementalChararacter2, supplementalChararacter2];
    shouldBeEqual(resultString, expectedResultString);
}

// We expect sequential string children under an element to get merged.
- (void)testStringConcat;
{
    NSString *xmlString = @"<root>a &amp; b</root>";
    NSData *xmlData = [xmlString dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error = nil;
    
    OFXMLDocument *doc = [[[OFXMLDocument alloc] initWithData:xmlData whitespaceBehavior:nil error:&error] autorelease];
    
    OFXMLElement *rootElement = [doc rootElement];
    STAssertEqualObjects([rootElement name], @"root", @"root name");
    
    // There will have been a 'characters', 'entity mapped to charaters' and then 'characters' callback.  These should all get merged.
    should([[rootElement children] count] == 1);
    STAssertEqualObjects([[rootElement children] lastObject], @"a & b", @"string concat");
}

- (void) testEntityReading;
{
    NSString *sourceString;

    sourceString =
        @"<root-element>"
        @"<s attr=\"&amp;\">&amp;</s>"
        @"<s attr=\"&amp;amp;\">&amp;amp;</s>"
        @"<s attr=\"&lt;\">&lt;</s>"
        @"<s attr=\"&amp;lt;\">&amp;lt;</s>"
        @"<s attr=\"&gt;\">&gt;</s>"
        @"<s attr=\"&amp;gt;\">&amp;gt;</s>"
        @"<s attr=\"&apos;\">&apos;</s>"
        @"<s attr=\"&amp;apos;\">&amp;apos;</s>"
        @"<s attr=\"&quot;\">&quot;</s>"
        @"<s attr=\"&amp;quot;\">&amp;quot;</s>"
        @"<s attr=\"&#35;\">&#35;</s>"
        @"<s attr=\"&#x35;\">&#x35;</s>"
        @"<s attr=\"&#65536;\">&#65536;</s>"
        @"<s attr=\"&#x10000;\">&#x10000;</s>"
        @"<s attr=\"a&amp;b\">a&amp;b</s>"
        @"<s attr=\"a &amp; b\">a &amp; b</s>"
        @"</root-element>";
    NSData *xmlData;

    xmlData = [sourceString dataUsingEncoding: NSUTF8StringEncoding];
    NSError *error = nil;
    OFXMLDocument *doc = [[[OFXMLDocument alloc] initWithData:xmlData whitespaceBehavior:nil error:&error] autorelease];

    NSArray *elements = [[doc rootElement] children];

    NSString *composedSequence = [NSString stringWithCharacter:0x10000];
    //NSLog(@"composedSequence = %@", composedSequence);
    
#define CHECK(i, s) STAssertEqualObjects([[elements objectAtIndex:i] childAtIndex:0], s, @"child node"); STAssertEqualObjects([[elements objectAtIndex:i] attributeNamed:@"attr"], s, @"attribute value")
    CHECK( 0, @"&");
    CHECK( 1, @"&amp;");
    CHECK( 2, @"<");
    CHECK( 3, @"&lt;");
    CHECK( 4, @">");
    CHECK( 5, @"&gt;");
    CHECK( 6, @"'");
    CHECK( 7, @"&apos;");
    CHECK( 8, @"\"");
    CHECK( 9, @"&quot;");
    CHECK(10, @"#");
    CHECK(11, @"5");
    CHECK(12, composedSequence);
    CHECK(13, composedSequence);
    CHECK(14, @"a&b");
    CHECK(15, @"a & b");
#undef CHECK
}

// Copied from OO3
static OFXMLWhitespaceBehavior *_OOXMLWhitespaceBehavior(void)
{
    static OFXMLWhitespaceBehavior *whitespace = nil;

    if (!whitespace) {
        whitespace = [[OFXMLWhitespaceBehavior alloc] init];
        [whitespace setBehavior: OFXMLWhitespaceBehaviorTypeIgnore forElementName: @"outline"];

        // Anything that contains rich text in OO needs to consider whitespace important when writing XML (i.e., don't pretty-print the tree structure)
        [whitespace setBehavior: OFXMLWhitespaceBehaviorTypePreserve forElementName: @"rich-text"];
        //[whitespace setBehavior: OFXMLWhitespaceBehaviorTypePreserve forElementName: @"note"]; // These can directly contain rich text data w/o a 'rich-text' wrapper right now.  Probably a bug.
        [whitespace setBehavior: OFXMLWhitespaceBehaviorTypePreserve forElementName: @"header"];
        [whitespace setBehavior: OFXMLWhitespaceBehaviorTypePreserve forElementName: @"footer"];
    }
    return whitespace;
}

- (void) testReadingFileWithWhitespaceHandling;
{
    NSString *inputFile;
    OFXMLDocument *doc;

    inputFile = [[self bundle] pathForResource:@"0000-CreateDocument" ofType:@"xmloutline"];
    should(inputFile != nil);
    
    // Use the same whitespace handling rules as OO3 itself.  This should still produce identical output, but the intermediate document object should have whitespace stripped where it would be ignored anyway.
    NSError *error = nil;
    doc = [[OFXMLDocument alloc] initWithContentsOfFile:inputFile whitespaceBehavior:_OOXMLWhitespaceBehavior() error:&error];
    should(doc != nil);
    
    NSData *inputData = [[NSData alloc] initWithContentsOfFile:inputFile];
    NSString *inputString = (NSString *)CFStringCreateFromExternalRepresentation(kCFAllocatorDefault, (CFDataRef)inputData, [doc stringEncoding]);
    [inputData release];

    SAVE_AND_COMPARE(inputString);
    [inputString release];

    [doc release];
}

- (void)testRoundTripProcessingInstructions;
{
    NSString *inputString =
    @"<?xml version=\"1.0\" encoding=\"utf-8\" standalone=\"no\"?>\n"
    @"<?my-pi foozle?>\n"
    @"<?empty-pi?>\n"
    @"<root-element/>\n";

    NSData *inputData = [inputString dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error = nil;
    OFXMLDocument *doc = [[[OFXMLDocument alloc] initWithData:inputData whitespaceBehavior:IgnoreAllWhitespace() error:&error] autorelease];
    OBShouldNotError(doc != nil);
    
    NSData *outputData = [doc xmlData:&error];
    OBShouldNotError(outputData != nil);
    
    NSString *outputString = [NSString stringWithData:outputData encoding:NSUTF8StringEncoding];
    shouldBeEqual(inputString, outputString);
}

// CDATA blocks should be converted to strings and merged with any surrounding strings.
- (void)testCDATAMerging;
{
    NSString *inputString =
    @"<?xml version=\"1.0\" encoding=\"utf-8\" standalone=\"no\"?>\n"
    @"<?my-pi foozle?>\n"
    @"<?empty-pi?>\n"
    @"<root-element>foo<![CDATA[<wonga>]]>blegga</root-element>\n";

    NSData *inputData = [inputString dataUsingEncoding:NSUTF8StringEncoding];
    NSError *error = nil;
    OFXMLDocument *doc = [[[OFXMLDocument alloc] initWithData:inputData whitespaceBehavior:IgnoreAllWhitespace() error:&error] autorelease];
    OFXMLElement *rootElement = [doc rootElement];
    
    should([[rootElement children] count] == 1);
    shouldBeEqual([[rootElement children] lastObject], @"foo<wonga>blegga");
}

- (void)testNilInputData;
{
    NSError *error = nil;
    OFXMLDocument *doc = [[[OFXMLDocument alloc] initWithData:nil whitespaceBehavior:IgnoreAllWhitespace() error:&error] autorelease];
    should(doc == nil);
}

@end
