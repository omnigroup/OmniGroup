// Copyright 2013-2014 Omni Development, Inc. All rights reserved.
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

#define CheckFontName(attrDict, expected) STAssertEqualObjects((NSString *)(attrDict[(id)kCTFontNameAttribute]), expected, @"Expected %@", expected)
#define CheckFontSize(attrDict, expected) STAssertEqualObjects((NSNumber *)(attributesFromFoundFont[(id)kCTFontSizeAttribute]), [NSNumber numberWithInt:expected], @"Expected %ld", expected)

static NSDictionary *_fontAttributesFromOAFontDescriptor(OAFontDescriptor *fontDescriptor)
{
    return  attributesFromFont(fontDescriptor.font);
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
    NSArray *result = [[NSFontManager sharedFontManager] availableFonts];
    return result;
#endif
}

+ (SenTest *)testForRoundTripOfFontName:(NSString *)fontName;
{
    NSInvocation *testInvocation = [NSInvocation invocationWithMethodSignature:[self instanceMethodSignatureForSelector:@selector(testRoundTripForFontNamed:)]];
    testInvocation.selector = @selector(testRoundTripForFontNamed:);
    [testInvocation setArgument:&fontName atIndex:2];
    [testInvocation retainArguments];
    
    return [self testCaseWithInvocation:testInvocation];
}

+ (id)defaultTestSuite;
{
    SenTestSuite *suite = [super defaultTestSuite];

    NSArray *fontNamesToTest = [self _fontNamesToTest];
    for (NSString *fontName in fontNamesToTest) {
        [suite addTest:[self testForRoundTripOfFontName:fontName]];
    }
    
    return suite;
}

- (void)setUp;
{
    _helvetica12 = [[OAFontDescriptor alloc] initWithFamily:@"Helvetica" size:0];
}

- (void)tearDown;
{
    [_helvetica12 release];
    _helvetica12 = nil;
}

- (void)_assertIsHelvetica12Attributes:(NSDictionary *)attributesFromFoundFont;
{
    STAssertNotNil(attributesFromFoundFont, nil);
    CheckFontName(attributesFromFoundFont, @"Helvetica");
    CheckFontSize(attributesFromFoundFont, 12);
}

- (void)_assertIsHelvetica12BoldAttributes:(NSDictionary *)attributesFromFoundFont;
{
    STAssertNotNil(attributesFromFoundFont, nil);
    // boldness is absorbed into the font name, eek
    {
        CheckFontName(attributesFromFoundFont, @"Helvetica-Bold");
        STAssertNil(attributesFromFoundFont[(id)kCTFontTraitsAttribute][(id)kCTFontSymbolicTrait], @"Expect no symbolic trait to be set");
    }
    CheckFontSize(attributesFromFoundFont, 12);
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
    
    STAssertNotNil(attributesFromFoundFont, nil);
    CheckFontName(attributesFromFoundFont, @"Helvetica");
    CGFloat expected = 12.9;
    STAssertEqualsWithAccuracy([(NSNumber *)(attributesFromFoundFont[(id)kCTFontSizeAttribute]) cgFloatValue], (CGFloat)expected, 0.05, @"Expected %lf", expected);
}

- (void)testHelvetica13;
{
    NSDictionary *attributesFromFoundFont = _fontAttributesFromOAFontDescriptor([[[OAFontDescriptor alloc] initWithFamily:@"Helvetica" size:13] autorelease]);
    
    STAssertNotNil(attributesFromFoundFont, nil);
    CheckFontName(attributesFromFoundFont, @"Helvetica");
    CheckFontSize(attributesFromFoundFont, 13);
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
    
    STAssertNotNil(attributesFromFoundFont, nil);
    // boldness is absorbed into the font name, eek
    {
        CheckFontName(attributesFromFoundFont, @"Helvetica-Bold");
        STAssertNil(attributesFromFoundFont[(id)kCTFontTraitsAttribute][(id)kCTFontSymbolicTrait], @"Expect no symbolic trait to be set");
    }
    CGFloat expected = 12.9;
    STAssertEqualsWithAccuracy([(NSNumber *)(attributesFromFoundFont[(id)kCTFontSizeAttribute]) cgFloatValue], (CGFloat)expected, 0.05, @"Expected %lf", expected);
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
    [self _assertIsHelvetica12Attributes:attributesFromFoundFont];
}


- (void)testHelveticaSemibold;
{
    OAFontDescriptor *descriptor = [[_helvetica12 newFontDescriptorWithWeight:8] autorelease];
    NSDictionary *attributesFromFoundFont = _fontAttributesFromOAFontDescriptor(descriptor);
    
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
    [self _assertIsHelvetica12Attributes:attributesFromFoundFont];
#else
    STAssertNotNil(attributesFromFoundFont, nil);
    CheckFontName(attributesFromFoundFont, @"Helvetica-Bold"); // No semi-bold installed on the Mac by default
    CheckFontSize(attributesFromFoundFont, 12);
#endif
}

- (void)testHelveticaItalic;
{
    OAFontDescriptor *descriptor = [[_helvetica12 newFontDescriptorWithItalic:YES] autorelease];
    NSDictionary *attributesFromFoundFont = _fontAttributesFromOAFontDescriptor(descriptor);
    STAssertNotNil(attributesFromFoundFont, nil);
    // italics is absorbed into the font name, eek
    {
        CheckFontName(attributesFromFoundFont, @"Helvetica-Oblique");
        STAssertNil(attributesFromFoundFont[(id)kCTFontTraitsAttribute][(id)kCTFontSymbolicTrait], @"Expect no symbolic trait to be set");
    }
    CheckFontSize(attributesFromFoundFont, 12);
}

- (void)testHoeflerText;
{
    OAFontDescriptor *descriptor = [[_helvetica12 newFontDescriptorWithFamily:@"Hoefler Text"] autorelease];
    NSDictionary *attributesFromFoundFont = _fontAttributesFromOAFontDescriptor(descriptor);
    STAssertNotNil(attributesFromFoundFont, nil);
    CheckFontName(attributesFromFoundFont, @"HoeflerText-Regular");
    CheckFontSize(attributesFromFoundFont, 12);
}

- (void)testSizeChange;
{
    OAFontDescriptor *descriptor = [[_helvetica12 newFontDescriptorWithSize:16] autorelease];
    NSDictionary *attributesFromFoundFont = _fontAttributesFromOAFontDescriptor(descriptor);
    STAssertNotNil(attributesFromFoundFont, nil);
    CheckFontName(attributesFromFoundFont, @"Helvetica");
    CheckFontSize(attributesFromFoundFont, 16);
}

- (void)testBigInitializer;
{
    OAFontDescriptor *descriptor = [[[OAFontDescriptor alloc] initWithFamily:@"Helvetica" size:24 weight:9 italic:YES condensed:NO fixedPitch:NO] autorelease];
    NSDictionary *attributesFromFoundFont = _fontAttributesFromOAFontDescriptor(descriptor);
    STAssertNotNil(attributesFromFoundFont, nil);
    // bold italic is absorbed into the font name, eek
    {
        CheckFontName(attributesFromFoundFont, @"Helvetica-BoldOblique");
        STAssertNil(attributesFromFoundFont[(id)kCTFontTraitsAttribute][(id)kCTFontSymbolicTrait], @"Expect no symbolic trait to be set");
    }
    CheckFontSize(attributesFromFoundFont, 24);
}

- (void)testZapfino36;
{
    OAFontDescriptor *descriptor = [[[OAFontDescriptor alloc] initWithFamily:@"Zapfino" size:36] autorelease];
    NSDictionary *attributesFromFoundFont = _fontAttributesFromOAFontDescriptor(descriptor);
    STAssertNotNil(attributesFromFoundFont, nil);
    CheckFontName(attributesFromFoundFont, @"Zapfino");
    CheckFontSize(attributesFromFoundFont, 36);
}

- (void)testZapfinoAlmost36;
{
    OAFontDescriptor *descriptor = [[[OAFontDescriptor alloc] initWithFamily:@"Zapfino" size:35.8] autorelease];
    NSDictionary *attributesFromFoundFont = _fontAttributesFromOAFontDescriptor(descriptor);
    STAssertNotNil(attributesFromFoundFont, nil);
    CheckFontName(attributesFromFoundFont, @"Zapfino");
    CGFloat expected = 35.8;
    STAssertEqualsWithAccuracy([(NSNumber *)(attributesFromFoundFont[(id)kCTFontSizeAttribute]) cgFloatValue], (CGFloat)expected, 0.05, @"Expected %lf", expected);
}

- (void)testCromulentFont;
{
    OAFontDescriptor *descriptor = [[[OAFontDescriptor alloc] initWithFamily:@"ThisFontIsPerfectlyCromulent" size:10] autorelease];
    NSDictionary *attributesFromFoundFont = _fontAttributesFromOAFontDescriptor(descriptor);
    STAssertNotNil(attributesFromFoundFont, nil);
    NSString *expectedFontNameForPlatform = nil;
    expectedFontNameForPlatform = @"Helvetica";
    CheckFontName(attributesFromFoundFont, expectedFontNameForPlatform); // Expect to fail family look up and fall back to default
    CheckFontSize(attributesFromFoundFont, 10);
}

- (void)testFixedPitchHoeflerText;
{
    // There is no fixed-pitch Hoefler Text, but let's check our fall-back path
    OAFontDescriptor *descriptor = [[[OAFontDescriptor alloc] initWithFamily:@"Hoefler Text" size:12.0f weight:5 italic:NO condensed:NO fixedPitch:YES] autorelease];
    NSDictionary *attributesFromFoundFont = _fontAttributesFromOAFontDescriptor(descriptor);
    STAssertNotNil(attributesFromFoundFont, nil);
    CheckFontName(attributesFromFoundFont, @"HoeflerText-Regular");
    CheckFontSize(attributesFromFoundFont, 12);
}

- (void)testBoldFixedPitchHoeflerText;
{
    // There is no fixed-pitch Hoefler Text, but let's check our fall-back path
    OAFontDescriptor *descriptor = [[[OAFontDescriptor alloc] initWithFamily:@"Hoefler Text" size:12.0f weight:9 italic:NO condensed:NO fixedPitch:YES] autorelease];
    NSDictionary *attributesFromFoundFont = _fontAttributesFromOAFontDescriptor(descriptor);
    STAssertNotNil(attributesFromFoundFont, nil);
    CheckFontName(attributesFromFoundFont, @"HoeflerText-Black");
    CheckFontSize(attributesFromFoundFont, 12);
}

- (void)testRoundTripForFontNamed:(NSString *)fontName;
{
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
    UIFont *font = [UIFont fontWithName:fontName size:12];
    NSString *nameFromFont = font.fontName;
    STAssertEqualObjects(fontName, nameFromFont, @"Asked for font named “%@”, but got font named “%@”.", fontName, nameFromFont);
    
    OAFontDescriptor *descriptor = [[[OAFontDescriptor alloc] initWithFont:font] autorelease];
    
    UIFont *roundTrippedFont = descriptor.font;
    NSString *nameFromRoundTrippedFont = roundTrippedFont.fontName;
    STAssertEqualObjects(nameFromFont, nameFromRoundTrippedFont, @"Started with font named “%@”. After round-tripping got “%@”.", nameFromFont, nameFromRoundTrippedFont);
#else
    NSFont *font = [NSFont fontWithName:fontName size:12.0f];
    NSString *nameFromFontRef = font.fontName;
    STAssertEqualObjects(fontName, nameFromFontRef, @"Asked for font named “%@”, but got font named “%@”.", fontName, nameFromFontRef);

    OAFontDescriptor *descriptor = [[[OAFontDescriptor alloc] initWithFont:font] autorelease];
    
    NSFont *roundTrippedFont = descriptor.font;
    NSString *nameFromRoundTrippedFontRef = roundTrippedFont.fontName;
    STAssertEqualObjects(nameFromFontRef, nameFromRoundTrippedFontRef, @"Started with font named “%@”. After round-tripping got “%@”.", nameFromFontRef, nameFromRoundTrippedFontRef);
#endif
}

@end

