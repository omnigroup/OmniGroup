// Copyright 2009-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFXMLMaker.h>
#import <OmniFoundation/OFXMLTextWriterSink.h>

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <XCTest/XCTest.h>

#import <OmniFoundation/NSObject-OFExtensions.h>
#import <OmniFoundation/NSString-OFExtensions.h>
#import <OmniFoundation/OFScratchFile.h>

#include <libxml/xmlwriter.h>

#import "OFTestCase.h"

RCS_ID("$Id$");

static NSString *xmlnsXML = @"http://www.w3.org/XML/1998/namespace";
// static NSString *xmlnsXMLNS = @"http://www.w3.org/2000/xmlns/";

static NSString *xmlnsSVG = @"http://www.w3.org/2000/svg";
static NSString *xmlnsXLink = @"http://www.w3.org/1999/xlink";
static NSString *xmlnsDublinCore = @"http://purl.org/dc/elements/1.1/";
static NSString *xmlnsOO3 = @"http://www.omnigroup.com/namespace/OmniOutliner/v3";
static NSString *xmlnsSillyExample = @"tel:+1-206-523-4152";

@interface OFXMLMakerTests : XCTestCase
{
    OFXMLSink *sink;
}

- (void)getSink;
- (void)closeSinkAndCompare:(NSString *)toDoc;

@end


@implementation OFXMLMakerTests

// Customized test suite
+ (XCTestSuite *)defaultTestSuite;
{
    if (self == [OFXMLMakerTests class]) {
        return [[XCTestSuite alloc] initWithName:@"OFXMLMakerTests"];
    }

    return [super defaultTestSuite];
}

- (void)dealloc
{
    sink = nil;
}

- (void)setUp;
{
    NSLog(@"%@ %@", OBShortObjectDescription(self), NSStringFromSelector(_cmd));
}

- (void)getSink;
{
    OBRequestConcreteImplementation(self, _cmd);
}

- (void)closeSinkAndCompare:(NSString *)toDoc;
{
    OBRequestConcreteImplementation(self, _cmd);
}

// Test cases
#pragma mark Generic test cases

- (void)testAttributeValues
{
    [self getSink];
    
    /* Here we're setting the encoding to a non-default value so we can also test utf-8 output */
    [sink setEncodingName:@"utf-8"];
    [sink addXMLDeclaration];
    
    OFXMLMakerElement *elt = [sink openElement:@"foo"];
    [elt addAttribute:@"singlequote" value:@"it's"];
    [elt addAttribute:@"doublequote" value:@"a 1/4\" plug"];
    [elt addAttribute:@"bothquotes" value:@"it's a 1/4\" plug"];  // actual cfxml failure case
    [elt addAttribute:@"emptystring" value:@""];
    [elt addAttribute:@"ampersand" value:@"rhythm&blues"];
    [elt addAttribute:@"nonascii" value:@"\u2200p p\u2286q"];
    
    [elt close];
    
    [self closeSinkAndCompare:[[[self class] bundle] pathForResource:@"0003-attrs" ofType:@"xml"]];
}

- (void)testOtherEncoding
{
    [self getSink];
    
    /* Neither US-ASCII nor UTF-8 ! */
    [sink setEncodingName:@"utf-16"];
    [sink addXMLDeclaration];
    
    OFXMLMakerElement *elt = [sink openElement:@"foo"];
    [elt addString:@"This\u266B"];
    [elt close];
    
    [self closeSinkAndCompare:[[[self class] bundle] pathForResource:@"0004-utf16" ofType:@"xml"]];
}

- (void)testSampleDoc
{
    [self getSink];
    
    [sink setEncodingName:@"utf-8"];
    [sink setIsStandalone:NO];
    [sink addXMLDeclaration];
    [sink addDoctype:@"outline" identifiers:@"-//omnigroup.com//DTD OUTLINE 3.0//EN" :@"xmloutline-v3.dtd"];

    OFXMLMakerElement *outline = [sink openElement:@"outline" xmlns:xmlnsOO3 defaultNamespace:xmlnsOO3];
    [outline addAttribute:@"version" value:@"1.0"];
    [[outline openElement:@"attachments"] close];
    {
        OFXMLMakerElement *cols = [outline openElement:@"columns"];
        
        OFXMLMakerElement *noteColumn = [cols openElement:@"column"];
        [noteColumn addAttribute:@"type"               value:@"rich-text"];
        [noteColumn addAttribute:@"width"              value:@"13"];
        [noteColumn addAttribute:@"minimum-width"      value:@"13"];
        [noteColumn addAttribute:@"maximum-width"      value:@"30"];
        [noteColumn addAttribute:@"text-export-width"  value:@"1"];
        [noteColumn addAttribute:@"is-note-column"     value:@"yes"];
        [[noteColumn openElement:@"title"] close];
        [noteColumn close];
        
        OFXMLMakerElement *topicColumn = [cols openElement:@"column"];
        [topicColumn addAttribute:@"type"               value:@"rich-text"];
        [topicColumn addAttribute:@"width"              value:@"512"];
        [topicColumn addAttribute:@"minimum-width"      value:@"13"];
        [topicColumn addAttribute:@"maximum-width"      value:@"1000000"];
        [topicColumn addAttribute:@"text-export-width"  value:@"72"];
        [topicColumn addAttribute:@"is-outline-column"     value:@"yes"];
        [[[topicColumn openElement:@"title"] addString:@"Topic"] close];
        [topicColumn close];
        
        [cols close];
    }

    {
        OFXMLMakerElement *levels = [outline openElement:@"level-styles"];
        for(int styleNumber = 0; styleNumber < 2; styleNumber ++) {
            OFXMLMakerElement *style = [levels openElement:@"level-style"];
            [[[style openElement:@"text-color"] addString:@"#000000"] close];
            [[[style openElement:@"font-family"] addString:@"Helvetica"] close];
            [[[style openElement:@"font-size"] addString:@"12"] close];
            [[[style openElement:@"heading"] addAttribute:@"type" value:@"None"] close];
            [style close];
        }
        [levels close];
    }
    
    {
        OFXMLMakerElement *outlineRoot = [outline openElement:@"root"];
        [outlineRoot addAttribute:@"background-color" value:@"#ffffff"];
        OFXMLMakerElement *solitaryItem = [outlineRoot openElement:@"item"];
        OFXMLMakerElement *itemValues = [solitaryItem openElement:@"values"];
        OFXMLMakerElement *text = [itemValues openElement:@"rich-text"];
        [[text openElement:@"p"] close];
        [text close];
        [itemValues close];
        [solitaryItem close];
        [outlineRoot close];
    }
    
    {
        OFXMLMakerElement *outlineSettings = [outline openElement:@"settings"];
        
        [[[outlineSettings openElement:@"note-height"] addString:@"100"] close];
        [[[outlineSettings openElement:@"is-status-visible"] addString:@"yes"] close];
        [[[outlineSettings openElement:@"is-spellchecking-enabled"] addString:@"yes"] close];
        [[[outlineSettings openElement:@"is-note-expanded"] addString:@"yes"] close];
        [[[outlineSettings openElement:@"should-print-column-headers"] addString:@"yes"] close];
        [[[outlineSettings openElement:@"should-print-notes"] addString:@"yes"] close];
        [[[outlineSettings openElement:@"should-print-background"] addString:@"yes"] close];
        
        OFXMLMakerElement *adornment = [outlineSettings openElement:@"page-adornment"];
        [adornment addAttribute:@"header-top-margin" value:@"36"];
        [adornment addAttribute:@"header-bottom-margin" value:@"36"];
        [adornment addAttribute:@"footer-top-margin" value:@"36"];
        [adornment addAttribute:@"footer-bottom-margin" value:@"36"];
        [adornment close];
        
        OFXMLMakerElement *printInfo = [outlineSettings openElement:@"print-info"];
        NSData *archivedPrintInfo = [NSData dataWithBytesNoCopy:
                                     "\x04\x0Btypedstream\x81\x03\xE8\x84\x01@\x84\x84\x84\x0BNSPrintInfo"
                                     "\x01\x84\x84\x08NSObject\x00\x85\x92\x84\x84\x84\x13NSMutableDictionar"
                                     "y\x00\x84\x84\x0CNSDictionary\x00\x94\x84\x01i\x08\x92\x84\x84\x84\x08"
                                     "NSString\x01\x94\x84\x01+\x0ENSBottomMargin\x86\x92\x84\x84\x84\x08NSN"
                                     "umber\x00\x84\x84\x07NSValue\x00\x94\x84\x01*\x84\x84\x01" "f\x9D$\x86"
                                     "\x92\x84\x99\x99\x14NSVerticallyCentered\x86\x92\x84\x9B\x9C\x84\x84"
                                     "\x01" "c\x9E\x00\x86\x92\x84\x99\x99\x0CNSLeftMargin\x86\x92\x84\x9B"
                                     "\x9C\x9D\x9D$\x86\x92\x84\x99\x99\rNSRightMargin\x86\x92\x84\x9B\x9C"
                                     "\x9D\x9D$\x86\x92\x84\x99\x99\x14NSVerticalPagination\x86\x92\x84\x9B"
                                     "\x9C\x84\x97\x97\x00\x86\x92\x84\x99\x99\x16NSHorizontallyCentered\x86"
                                     "\x92\x9F\x92\x84\x99\x99\x0BNSTopMargin\x86\x92\x84\x9B\x9C\x9D\x9D$"
                                     "\x86\x92\x84\x99\x99\x15NSHorizonalPagination\x86\x92\x84\x9B\x9C\xA7"
                                     "\x97\x00\x86\x86\x86"
                                                         length:381
                                                   freeWhenDone:NO];
        [printInfo addBase64Data:archivedPrintInfo];
        [printInfo close];
        
        [outlineSettings close];
    }
    
    [[[outline openElement:@"conduit-settings"] addAttribute:@"has-outline-changed" value:@"yes"] close];
    
    [outline close];
    
    [self closeSinkAndCompare:[[[self class] bundle] pathForResource:@"0000-CreateDocument" ofType:@"xmloutline"]];
}

struct {
    __unsafe_unretained NSString *illumId;
    int cx, cy;
    __unsafe_unretained NSString *url;
} shapes[3] = {
{ @"illum1", 115, 46, @"http://www.omnigroup.com/" },
{ @"illum2", 212, 46, @"http://www.omnigroup.com/applications" },
{ @"illum3", 307, 46, @"http://www.omnigroup.com/support" }
};

- (void)testNamespaces
{
    int shape;
    
    [self getSink];
    [sink setEncodingName:@"utf-8"];

    [sink addXMLDeclaration];
    [sink addDoctype:@"svg" identifiers:@"-//W3C//DTD SVG 1.1//EN" :@"http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd"];

    OFXMLMakerElement *svg = [sink openElement:@"svg" xmlns:xmlnsSVG defaultNamespace:xmlnsSVG];
    [svg prefixForNamespace:xmlnsXLink hint:@"xl"];
    [svg addAttribute:@"version" xmlns:xmlnsSVG value:@"1.1"];
    
    /* size */
    [svg addAttribute:@"viewBox" value:@"0 0 450 140"];
    [svg addAttribute:@"width" value:@"450pt"];
    [svg addAttribute:@"height" value:@"140pt"];
    
    
    /* metadata, with a local namespace declaration */
    OFXMLMakerElement *meta = [svg openElement:@"metadata"];
    [meta prefixForNamespace:xmlnsDublinCore hint:@"dc"];
    [[[meta openElement:@"description" xmlns:xmlnsDublinCore] addString:@"An example of an SVG document."] close];
    [meta close];
    
    /* a defs element to hold some filters */
    OFXMLMakerElement *defs = [svg openElement:@"defs" xmlns:xmlnsSVG]; // Explicitly specifying xmlns; should have no effect since that's currently the default namespace
    OFXMLMakerElement *filter = [defs openElement:@"radialGradient"];
    [[filter addAttribute:@"id" value:@"generic_illumination"] addAttribute:@"gradientUnits" value:@"userSpaceOnUse"];
    [[[filter addAttribute:@"cx" value:@"0"] addAttribute:@"cy" value:@"0"] addAttribute:@"r" value:@"52"];
    [[[[filter openElement:@"stop"] addAttribute:@"offset" value:@"0"] addAttribute:@"stop-color" value:@"#fff"] close];
    [[[[filter openElement:@"stop"] addAttribute:@"offset" value:@"1"] addAttribute:@"stop-color" value:@"#aaa"] close];
    [filter close];
    
    /* variations of that gradient shifted to lie under each "sphere" */
    for(shape = 0; shape < 3; shape ++) {
        OFXMLMakerElement *actual = [defs openElement:@"radialGradient"];
        [actual addAttribute:@"id" value:shapes[shape].illumId];
        [actual addAttribute:@"href" xmlns:xmlnsXLink value:@"#generic_illumination"];
        [actual addAttribute:@"gradientTransform" value:[NSString stringWithFormat:@"translate(%.1f %.1f)", shapes[shape].cx + 8.7, shapes[shape].cy - 11.5]];
        [actual close];
    }
    
    [defs close];
    
    /* the actual drawing */
    OFXMLMakerElement *group = [svg openElement:@"g"];
    [[[group addAttribute:@"stroke" value:@"black"] addAttribute:@"stroke-opacity" value:@"1"] addAttribute:@"fill-opacity" value:@"1"];
    
    [[[[group openElement:@"path"] addAttribute:@"d" value:@"M 82 28 L 19 116 L 357 116 L 417 27 Z"] addAttribute:@"fill" value:@"white"] close];
    
    for(shape = 0; shape < 3; shape ++) {
        OFXMLMakerElement *link = [[group openElement:@"a"] addAttribute:@"href" xmlns:xmlnsXLink value:shapes[shape].url];
        [[[[[[link openElement:@"circle"] addAttribute:@"cx" value:[NSString stringWithFormat:@"%d", shapes[shape].cx]]  addAttribute:@"cy" value:[NSString stringWithFormat:@"%d", shapes[shape].cy]]  addAttribute:@"r" value:@"32"] addAttribute:@"fill" value:[NSString stringWithFormat:@"url(#%@)", shapes[shape].illumId]] close];
        [link close];
    }
    [group close];
    
    [svg close];
    
    [self closeSinkAndCompare:[[[self class] bundle] pathForResource:@"0001-Namespaces" ofType:@"svg"]];
}

@end

#pragma mark libxml2 xmlwriter tests

@interface OFXMLMakerTests_TextWriter : OFXMLMakerTests
{
    OFScratchFile *outputFile;
}
@end

@implementation OFXMLMakerTests_TextWriter

- (void)getSink
{
    OBPRECONDITION(sink == nil);
    OBPRECONDITION(outputFile == nil);
    
    outputFile = [OFScratchFile scratchFileNamed:@"libxml2-out-raw" error:NULL];
    NSURL *outputURL = outputFile.fileURL;
    CFDataRef urlBytes = CFURLCreateData(kCFAllocatorDefault, (CFURLRef)outputURL, kCFStringEncodingUTF8, true);
    CFMutableDataRef terminatedURLBytes = CFDataCreateMutableCopy(kCFAllocatorDefault, 0, urlBytes);
    CFDataAppendBytes(terminatedURLBytes, (const UInt8 *)"", 1);
    NSLog(@"Sending to: %s", CFDataGetBytePtr(terminatedURLBytes));
    xmlTextWriter *w = xmlNewTextWriterFilename((const char *)CFDataGetBytePtr(terminatedURLBytes), 0);
    
    /* Set the prettyprinting of this writer to match our test docs */
    xmlTextWriterSetIndent(w, 1);
    xmlTextWriterSetIndentString(w, BAD_CAST "  ");
    
    CFRelease(urlBytes);
    sink = [[OFXMLTextWriterSink alloc] initWithTextWriter:w freeWhenDone:YES];
    
    CFRelease(terminatedURLBytes);
    
    OBPOSTCONDITION(sink != nil);
}

- (void)closeSinkAndCompare:(NSString *)referenceDoc
{
    OBPRECONDITION(sink != nil);
    OBPRECONDITION(referenceDoc != nil);
    
    [sink close];
    
    OFDiffFiles(self, referenceDoc, [outputFile.fileURL path], nil/*operations*/);
}

@end


