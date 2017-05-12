// Copyright 2007-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OATestCase.h"

#import <AppKit/AppKit.h>
#import <OmniBase/rcsid.h>
#import <OmniAppKit/NSColor-OAExtensions.h>

RCS_ID("$Id$")

@interface OAColorArchivingTests : OATestCase
@end

@implementation OAColorArchivingTests

static void _checkFile(OAColorArchivingTests *self, NSString *path, NSData *actualData)
{
    // We expect to be run from the OmniAppKit folder
    path = [[NSBundle bundleForClass:[self class]] pathForResource:path ofType:nil];
    XCTAssertNotNil(path, @"Expected to find test data resource \"%@\"", path);
    if (!path)
        return;
    
    // We don't expect the data to be identical
    NSData *expectedData = [NSData dataWithContentsOfFile:path];
    XCTAssertNotNil(expectedData, @"should have expected data in %@", path);
    if (OFNOTEQUAL(expectedData, actualData)) {
        NSString *actualPath = [@"/tmp" stringByAppendingPathComponent:[path lastPathComponent]];
        NSLog(@"Archived color data does not match expected data: [diff %@ %@]", path, actualPath);
        [actualData writeToFile:actualPath atomically:YES];
    }
    XCTAssertEqualObjects(expectedData, actualData, @"archived colors should be equal");
}

static BOOL _compareColors(NSColor *a, NSColor *b)
{
    if ([[a colorSpaceName] isEqualToString:NSPatternColorSpace] && [[b colorSpaceName] isEqualToString:NSPatternColorSpace]) {
        // NSImages are only -isEqual: if they are ==, which they won't be after an archive/unarchive.
        NSData *tiffA = [[a patternImage] TIFFRepresentation];
        NSData *tiffB = [[b patternImage] TIFFRepresentation];
        return OFISEQUAL(tiffA, tiffB);
    }
    
    return OFISEQUAL(a, b);
}

static void _checkPlist(OAColorArchivingTests *self, NSColor *color, NSDictionary *plist, NSString *name, SEL sel)
{
    XCTAssertNotNil(plist, @"shoud have made a plist");
    if (plist == nil)
        return;

    __autoreleasing NSError *error = nil;
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:plist format:NSPropertyListXMLFormat_v1_0 options:0 error:&error];
    XCTAssertNotNil(data, @"should get something back from archiving");
    
    if (!data)
        return;
    
    _checkFile(self, [NSString stringWithFormat:@"%@-%@", [NSStringFromSelector(sel) stringByRemovingPrefix:@"test"], name], data);
    
    // Don't add extra spurious failures on an encoding failure
    if (plist) {
        // Reconstitute the color and compare them.
        NSColor *unarchived = [NSColor colorFromPropertyListRepresentation:plist];
        XCTAssertTrue(_compareColors(color, unarchived), @"plist color archiving/unarchive should be idempotent");
    }
}

static void _checkColor(OAColorArchivingTests *self, NSColor *color, SEL sel)
{
    XCTAssertNotNil(color, @"shoud have gotten a color");
    if (color == nil)
        return;

    _checkPlist(self, color, [color propertyListRepresentationWithStringComponentsOmittingDefaultValues:YES], @"string-partial.plist", sel);
    _checkPlist(self, color, [color propertyListRepresentationWithStringComponentsOmittingDefaultValues:NO], @"string-full.plist", sel);

    _checkPlist(self, color, [color propertyListRepresentationWithNumberComponentsOmittingDefaultValues:YES], @"number-partial.plist", sel);
    _checkPlist(self, color, [color propertyListRepresentationWithNumberComponentsOmittingDefaultValues:NO], @"number-full.plist", sel);
    
    OFXMLWhitespaceBehavior *whitespace = [[[OFXMLWhitespaceBehavior alloc] init] autorelease];
    NSError *error = nil;
    OFXMLDocument *doc = [[[OFXMLDocument alloc] initWithRootElementName:@"ignored" namespaceURL:nil whitespaceBehavior:whitespace stringEncoding:kCFStringEncodingUTF8 error:&error] autorelease];
    OBShouldNotError(doc != nil);
    
    [color appendXML:doc];
    
    OFXMLElement *colorElement = [[[doc topElement] children] lastObject];
    
    NSData *xmlData = [colorElement xmlDataAsFragment:&error];
    OBShouldNotError(xmlData != nil);
    
    _checkFile(self, [NSString stringWithFormat:@"%@.xml", [NSStringFromSelector(sel) stringByRemovingPrefix:@"test"]], xmlData);
    
    // Don't add extra spurious failures on an encoding failure
    if (xmlData) {
        // Reconstitute the color and compare them.
        OFXMLCursor *cursor = [[[OFXMLCursor alloc] initWithDocument:doc element:colorElement] autorelease];
        NSColor *unarchived = [NSColor colorFromXML:cursor];
        XCTAssertTrue(_compareColors(color, unarchived), @"XML color archiving/unarchive should be idempotent");
    }
}

#define CHECK(x) _checkColor(self, x, _cmd)

- (void)testRGB;
{
    CHECK([NSColor colorWithRed:0.125f green:0.25f blue:0.5f alpha:1.0f]);
}

- (void)testRGBA;
{
    CHECK([NSColor colorWithRed:0.125f green:0.25f blue:0.5f alpha:0.75f]);
}

- (void)testWhite;
{
    CHECK([NSColor colorWithWhite:0.5f alpha:1.0f]);
}

- (void)testWhiteAlpha;
{
    CHECK([NSColor colorWithWhite:0.5f alpha:0.75f]);
}

- (void)testCatalog;
{
    CHECK([NSColor textColor]);
}

- (void)testHSV;
{
    CHECK([NSColor colorWithHue:0.75f saturation:0.5f brightness:0.25f alpha:1.0f]);
}

- (void)testHSVA;
{
    CHECK([NSColor colorWithHue:0.75f saturation:0.5f brightness:0.25f alpha:0.75f]);
}

- (void)testCMYK;
{
    const CGFloat components[5] = {0.125f, 0.25f, 0.5f, 0.625f, 1.0f};
    CHECK([NSColor colorWithColorSpace:[NSColorSpace genericCMYKColorSpace] components:components count:5]);
}

- (void)testCMYKA;
{
    const CGFloat components[5] = {0.125f, 0.25f, 0.5f, 0.625f, 0.75f};
    CHECK([NSColor colorWithColorSpace:[NSColorSpace genericCMYKColorSpace] components:components count:5]);
}

- (void)testPattern;
{
    NSImage *image = [NSImage imageNamed:@"pattern" inBundle:OMNI_BUNDLE];
    XCTAssertNotNil(image, @"image should exist");
    CHECK([NSColor colorWithPatternImage:image]);
}

@end
