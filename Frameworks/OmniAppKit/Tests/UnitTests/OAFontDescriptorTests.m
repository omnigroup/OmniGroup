// Copyright 2013-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OATestCase.h"
#import <OmniAppKit/OAFontDescriptor.h>

#import <Foundation/Foundation.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

#import <CoreText/CoreText.h> // OAFontDescriptor maps to CTFontDescriptor, so we'll need to adjust all this if we switch to NSFontDescriptor/UIFontDescriptor.
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#endif

RCS_ID("$Id$");

@interface OAFontDescriptorTests : OATestCase
@end

@implementation OAFontDescriptorTests
{
    OAFontDescriptor *_helvetica12;
}

#define CheckFontName(attrDict, expected) XCTAssertEqualObjects((NSString *)(attrDict[(id)kCTFontNameAttribute]), expected, @"Expected %@", expected)
#define CheckFontSize(attrDict, expected) XCTAssertEqualObjects((NSNumber *)(attributesFromFoundFont[(id)kCTFontSizeAttribute]), [NSNumber numberWithInt:expected], @"Expected %ld", expected)

static NSDictionary *_fontAttributesFromOAFontDescriptor(OAFontDescriptor *fontDescriptor)
{
    return  OAAttributesFromFont(fontDescriptor.font);
}

// This just returns every font name on the current system. That's a bit odd for a unit test, since the installed fonts will change the tests. On the other hand, most of the tests in this class depend on the installed fonts; it's the nature of this particular beast.
+ (NSArray *)_fontNamesToTest;
{
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
    NSMutableArray *fontNames = [NSMutableArray array];
    for (NSString *fontFamilyName in [UIFont familyNames]) {
        [fontNames addObjectsFromArray:[UIFont fontNamesForFamilyName:fontFamilyName]];
    }
    return fontNames;
#else
    // Some "special" fonts start with '.' and can't be looked up by normal means (CTFontDescriptorCreateMatchingFontDescriptors with the family name set will return nil). We could presumably look them up by specific font name, but then this isn't much of a test, so just skip any such fonts.
    
    NSArray *result = [[NSFontManager sharedFontManager] availableFonts];
    result = [result select:^BOOL(NSString *fontName) {
        return [fontName hasPrefix:@"."] == NO;
    }];
    
    return result;
#endif
}

+ (XCTest *)testForRoundTripOfFontName:(NSString *)fontName;
{
    NSInvocation *testInvocation = [NSInvocation invocationWithMethodSignature:[self instanceMethodSignatureForSelector:@selector(testRoundTripForFontNamed:)]];
    testInvocation.selector = @selector(testRoundTripForFontNamed:);
    [testInvocation setArgument:&fontName atIndex:2];
    [testInvocation retainArguments];
    
    return [self testCaseWithInvocation:testInvocation];
}

+ (XCTestSuite *)defaultTestSuite;
{
    XCTestSuite *suite = [super defaultTestSuite];

    NSArray *fontNamesToTest = [self _fontNamesToTest];
    for (NSString *fontName in fontNamesToTest) {
        [suite addTest:[self testForRoundTripOfFontName:fontName]];
    }
    
    return suite;
}

- (void)setUp;
{
    [super setUp];

    _helvetica12 = [[OAFontDescriptor alloc] initWithFamily:@"Helvetica" size:0];
}

- (void)tearDown;
{
    [_helvetica12 release];
    _helvetica12 = nil;

    [super tearDown];
}

- (void)_assertIsHelvetica12Attributes:(NSDictionary *)attributesFromFoundFont;
{
    XCTAssertNotNil(attributesFromFoundFont);
    CheckFontName(attributesFromFoundFont, @"Helvetica");
    CheckFontSize(attributesFromFoundFont, 12UL);
}

- (void)_assertIsHelvetica12LightAttributes:(NSDictionary *)attributesFromFoundFont;
{
    XCTAssert(attributesFromFoundFont);
    // lightness is absorbed into the font name, eek
    {
        CheckFontName(attributesFromFoundFont, @"Helvetica-Light");
        XCTAssertNil(attributesFromFoundFont[(id)kCTFontTraitsAttribute][(id)kCTFontSymbolicTrait], @"Expect no symbolic trait to be set");
    }
    CheckFontSize(attributesFromFoundFont, 12UL);
}

- (void)_assertIsHelvetica12BoldAttributes:(NSDictionary *)attributesFromFoundFont;
{
    XCTAssertNotNil(attributesFromFoundFont);
    // boldness is absorbed into the font name, eek
    {
        CheckFontName(attributesFromFoundFont, @"Helvetica-Bold");
        XCTAssertNil(attributesFromFoundFont[(id)kCTFontTraitsAttribute][(id)kCTFontSymbolicTrait], @"Expect no symbolic trait to be set");
    }
    CheckFontSize(attributesFromFoundFont, 12UL);
}

- (void)testGenericHelvetica;
{
    NSDictionary *attributesFromFoundFont = _fontAttributesFromOAFontDescriptor(_helvetica12);
    [self _assertIsHelvetica12Attributes:attributesFromFoundFont];
}

- (void)testHelvetica12;
{
    NSDictionary *attributesFromFoundFont = _fontAttributesFromOAFontDescriptor([[[OAFontDescriptor alloc] initWithFamily:@"Helvetica" size:12] autorelease]);
    [self _assertIsHelvetica12Attributes:attributesFromFoundFont];
}

- (void)testHelveticaAlmost13;
{
    NSDictionary *attributesFromFoundFont = _fontAttributesFromOAFontDescriptor([[[OAFontDescriptor alloc] initWithFamily:@"Helvetica" size:12.9] autorelease]);
    
    XCTAssertNotNil(attributesFromFoundFont);
    CheckFontName(attributesFromFoundFont, @"Helvetica");
    CGFloat expected = 12.9;
    XCTAssertEqualWithAccuracy([(NSNumber *)(attributesFromFoundFont[(id)kCTFontSizeAttribute]) cgFloatValue], (CGFloat)expected, 0.05, @"Expected %lf", expected);
}

- (void)testHelvetica13;
{
    NSDictionary *attributesFromFoundFont = _fontAttributesFromOAFontDescriptor([[[OAFontDescriptor alloc] initWithFamily:@"Helvetica" size:13] autorelease]);
    
    XCTAssertNotNil(attributesFromFoundFont);
    CheckFontName(attributesFromFoundFont, @"Helvetica");
    CheckFontSize(attributesFromFoundFont, 13UL);
}

- (void)testHelveticaBold;
{
    OAFontDescriptor *descriptor = [[_helvetica12 newFontDescriptorWithBold:YES] autorelease];
    NSDictionary *attributesFromFoundFont = _fontAttributesFromOAFontDescriptor(descriptor);
    [self _assertIsHelvetica12BoldAttributes:attributesFromFoundFont];
}

- (void)testHelveticaAlmost13Bold;
{
    OAFontDescriptor *descriptor = [[[[[OAFontDescriptor alloc] initWithFamily:@"Helvetica" size:12.9] autorelease] newFontDescriptorWithBold:YES] autorelease];
    NSDictionary *attributesFromFoundFont = _fontAttributesFromOAFontDescriptor(descriptor);
    
    XCTAssertNotNil(attributesFromFoundFont);
    // boldness is absorbed into the font name, eek
    {
        CheckFontName(attributesFromFoundFont, @"Helvetica-Bold");
        XCTAssertNil(attributesFromFoundFont[(id)kCTFontTraitsAttribute][(id)kCTFontSymbolicTrait], @"Expect no symbolic trait to be set");
    }
    CGFloat expected = 12.9;
    XCTAssertEqualWithAccuracy([(NSNumber *)(attributesFromFoundFont[(id)kCTFontSizeAttribute]) cgFloatValue], (CGFloat)expected, 0.05, @"Expected %lf", expected);
}

- (void)testHelveticaUnbold;
{
    OAFontDescriptor *descriptor = [[[[_helvetica12 newFontDescriptorWithBold:YES] autorelease] newFontDescriptorWithBold:NO] autorelease];
    NSDictionary *attributesFromFoundFont = _fontAttributesFromOAFontDescriptor(descriptor);
    [self _assertIsHelvetica12Attributes:attributesFromFoundFont];
}

- (void)testHelveticaBoldWeight;
{
    OAFontDescriptor *descriptor = [[_helvetica12 newFontDescriptorWithWeight:9] autorelease];
    NSDictionary *attributesFromFoundFont = _fontAttributesFromOAFontDescriptor(descriptor);
    [self _assertIsHelvetica12BoldAttributes:attributesFromFoundFont];
}

- (void)testHelveticaRegularWeight;
{
    OAFontDescriptor *descriptor = [[_helvetica12 newFontDescriptorWithWeight:5] autorelease];
    NSDictionary *attributesFromFoundFont = _fontAttributesFromOAFontDescriptor(descriptor);
    [self _assertIsHelvetica12Attributes:attributesFromFoundFont];
}

- (void)testHelveticaExtrablack;
{
    OAFontDescriptor *descriptor = [[_helvetica12 newFontDescriptorWithWeight:14] autorelease];
    NSDictionary *attributesFromFoundFont = _fontAttributesFromOAFontDescriptor(descriptor);
    [self _assertIsHelvetica12BoldAttributes:attributesFromFoundFont];
}

- (void)testHelveticaUltralight;
{
    OAFontDescriptor *descriptor = [[_helvetica12 newFontDescriptorWithWeight:1] autorelease];
    NSDictionary *attributesFromFoundFont = _fontAttributesFromOAFontDescriptor(descriptor);
    [self _assertIsHelvetica12LightAttributes:attributesFromFoundFont];
}


- (void)testHelveticaSemibold;
{
    OAFontDescriptor *descriptor = [[_helvetica12 newFontDescriptorWithWeight:8] autorelease];
    NSDictionary *attributesFromFoundFont = _fontAttributesFromOAFontDescriptor(descriptor);
    
    XCTAssertNotNil(attributesFromFoundFont);
    CheckFontName(attributesFromFoundFont, @"Helvetica-Bold"); // No semi-bold installed on the Mac by default
    CheckFontSize(attributesFromFoundFont, 12UL);
}

- (void)testHelveticaItalic;
{
    OAFontDescriptor *descriptor = [[_helvetica12 newFontDescriptorWithItalic:YES] autorelease];
    NSDictionary *attributesFromFoundFont = _fontAttributesFromOAFontDescriptor(descriptor);
    XCTAssertNotNil(attributesFromFoundFont);
    // italics is absorbed into the font name, eek
    {
        CheckFontName(attributesFromFoundFont, @"Helvetica-Oblique");
        XCTAssertNil(attributesFromFoundFont[(id)kCTFontTraitsAttribute][(id)kCTFontSymbolicTrait], @"Expect no symbolic trait to be set");
    }
    CheckFontSize(attributesFromFoundFont, 12UL);
}

- (void)testHoeflerText;
{
    OAFontDescriptor *descriptor = [[_helvetica12 newFontDescriptorWithFamily:@"Hoefler Text"] autorelease];
    NSDictionary *attributesFromFoundFont = _fontAttributesFromOAFontDescriptor(descriptor);
    XCTAssertNotNil(attributesFromFoundFont);
    CheckFontName(attributesFromFoundFont, @"HoeflerText-Regular");
    CheckFontSize(attributesFromFoundFont, 12UL);
}

- (void)testSizeChange;
{
    OAFontDescriptor *descriptor = [[_helvetica12 newFontDescriptorWithSize:16] autorelease];
    NSDictionary *attributesFromFoundFont = _fontAttributesFromOAFontDescriptor(descriptor);
    XCTAssertNotNil(attributesFromFoundFont);
    CheckFontName(attributesFromFoundFont, @"Helvetica");
    CheckFontSize(attributesFromFoundFont, 16UL);
}

- (void)testBigInitializer;
{
    OAFontDescriptor *descriptor = [[[OAFontDescriptor alloc] initWithFamily:@"Helvetica" size:24 weight:9 italic:YES condensed:NO fixedPitch:NO] autorelease];
    NSDictionary *attributesFromFoundFont = _fontAttributesFromOAFontDescriptor(descriptor);
    XCTAssertNotNil(attributesFromFoundFont);
    // bold italic is absorbed into the font name, eek
    {
        CheckFontName(attributesFromFoundFont, @"Helvetica-BoldOblique");
        XCTAssertNil(attributesFromFoundFont[(id)kCTFontTraitsAttribute][(id)kCTFontSymbolicTrait], @"Expect no symbolic trait to be set");
    }
    CheckFontSize(attributesFromFoundFont, 24UL);
}

- (void)testZapfino36;
{
    OAFontDescriptor *descriptor = [[[OAFontDescriptor alloc] initWithFamily:@"Zapfino" size:36] autorelease];
    NSDictionary *attributesFromFoundFont = _fontAttributesFromOAFontDescriptor(descriptor);
    XCTAssertNotNil(attributesFromFoundFont);
    CheckFontName(attributesFromFoundFont, @"Zapfino");
    CheckFontSize(attributesFromFoundFont, 36UL);
}

- (void)testZapfinoAlmost36;
{
    OAFontDescriptor *descriptor = [[[OAFontDescriptor alloc] initWithFamily:@"Zapfino" size:35.8] autorelease];
    NSDictionary *attributesFromFoundFont = _fontAttributesFromOAFontDescriptor(descriptor);
    XCTAssertNotNil(attributesFromFoundFont);
    CheckFontName(attributesFromFoundFont, @"Zapfino");
    CGFloat expected = 35.8;
    XCTAssertEqualWithAccuracy([(NSNumber *)(attributesFromFoundFont[(id)kCTFontSizeAttribute]) cgFloatValue], (CGFloat)expected, 0.05, @"Expected %lf", expected);
}

- (void)testBradleyHand; //this is interesting because in iOS 8.3 they seem to have added the "expanded" attribute to Bradley Hand, and that was preventing it from round-tripping
{
    OAFontDescriptor *descriptor = [[[OAFontDescriptor alloc] initWithFamily:@"Bradley Hand" size:20] autorelease];
    NSDictionary *attributesFromFoundFont = _fontAttributesFromOAFontDescriptor(descriptor);
    XCTAssertNotNil(attributesFromFoundFont);
    CheckFontName(attributesFromFoundFont, @"BradleyHandITCTT-Bold");
    CheckFontSize(attributesFromFoundFont, 20UL);
}

- (void)testCromulentFont;
{
    OAFontDescriptor *descriptor = [[[OAFontDescriptor alloc] initWithFamily:@"ThisFontIsPerfectlyCromulent" size:10] autorelease];
    NSDictionary *attributesFromFoundFont = _fontAttributesFromOAFontDescriptor(descriptor);
    XCTAssertNotNil(attributesFromFoundFont);
    NSString *expectedFontNameForPlatform = nil;
    expectedFontNameForPlatform = @"Helvetica";
    CheckFontName(attributesFromFoundFont, expectedFontNameForPlatform); // Expect to fail family look up and fall back to default
    CheckFontSize(attributesFromFoundFont, 10UL);
}

- (void)testFixedPitchHoeflerText;
{
    // There is no fixed-pitch Hoefler Text, but let's check our fall-back path
    OAFontDescriptor *descriptor = [[[OAFontDescriptor alloc] initWithFamily:@"Hoefler Text" size:12.0f weight:5 italic:NO condensed:NO fixedPitch:YES] autorelease];
    NSDictionary *attributesFromFoundFont = _fontAttributesFromOAFontDescriptor(descriptor);
    XCTAssertNotNil(attributesFromFoundFont);
    CheckFontName(attributesFromFoundFont, @"HoeflerText-Regular");
    CheckFontSize(attributesFromFoundFont, 12UL);
}

- (void)testBoldFixedPitchHoeflerText;
{
    // There is no fixed-pitch Hoefler Text, but let's check our fall-back path
    OAFontDescriptor *descriptor = [[[OAFontDescriptor alloc] initWithFamily:@"Hoefler Text" size:12.0f weight:9 italic:NO condensed:NO fixedPitch:YES] autorelease];
    NSDictionary *attributesFromFoundFont = _fontAttributesFromOAFontDescriptor(descriptor);
    XCTAssertNotNil(attributesFromFoundFont);
    CheckFontName(attributesFromFoundFont, @"HoeflerText-Black");
    CheckFontSize(attributesFromFoundFont, 12UL);
}

- (void)testRoundTripForFontNamed:(NSString *)fontName;
{
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
    UIFont *font = [UIFont fontWithName:fontName size:12];
    NSString *nameFromFont = font.fontName;
    XCTAssertEqualObjects(fontName, nameFromFont, @"Asked for font named “%@”, but got font named “%@”.", fontName, nameFromFont);
    
    OAFontDescriptor *descriptor = [[[OAFontDescriptor alloc] initWithFont:font] autorelease];
    
    UIFont *roundTrippedFont = descriptor.font;
    NSString *nameFromRoundTrippedFont = roundTrippedFont.fontName;
    XCTAssertEqualObjects(nameFromFont, nameFromRoundTrippedFont, @"Started with font named “%@”. After round-tripping got “%@”.", nameFromFont, nameFromRoundTrippedFont);
#else
    NSFont *font = [NSFont fontWithName:fontName size:12.0f];
    NSString *nameFromFontRef = font.fontName;
    XCTAssertEqualObjects(fontName, nameFromFontRef, @"Asked for font named “%@”, but got font named “%@”.", fontName, nameFromFontRef);

    OAFontDescriptor *descriptor = [[[OAFontDescriptor alloc] initWithFont:font] autorelease];
    
    NSFont *roundTrippedFont = descriptor.font;
    NSString *nameFromRoundTrippedFontRef = roundTrippedFont.fontName;
    XCTAssertEqualObjects(nameFromFontRef, nameFromRoundTrippedFontRef, @"Started with font named “%@”. After round-tripping got “%@”.", nameFromFontRef, nameFromRoundTrippedFontRef);
#endif
}

@end

