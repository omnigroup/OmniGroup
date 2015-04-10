// Copyright 2003-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFObject.h>
#import <OmniFoundation/OFExtent.h>
#import <Availability.h>

// On the Mac, NSFontDescriptor is toll-free bridged to CTFontDescriptorRef. NSFont doesn't seem to be bridged, but presumably each platform returns the appropriate font type.
// OBFinishPorting: is this still true in 7.0?
// On iPhone, there is no class to bridge to.  So, this class is currently a wrapper of a CTFontDescriptorRef instead of a subclass/replacement for NSFontDescriptor.

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
    #define OAPlatformFontClass UIFont
#else
    #import <ApplicationServices/ApplicationServices.h> // CoreText lives in this umbrella on the Mac
    #define OAPlatformFontClass NSFont
#endif
#define OAFontDescriptorPlatformFont OAPlatformFontClass *
@class OAPlatformFontClass;

@class NSNotification, NSDictionary;

extern NSInteger OAFontDescriptorRegularFontWeight(void); // NSFontManager-style weight
extern NSInteger OAFontDescriptorBoldFontWeight(void); // NSFontManager-style weight
extern OFExtent OAFontDescriptorValidFontWeightExtent(void);

// Returns the _minimal_ set of attributes (on iOS at least). Primarily useful for testing and debugging.
extern NSDictionary *attributesFromFont(OAFontDescriptorPlatformFont font);

@interface OAFontDescriptor : OFObject <NSCopying>

+ (void)forgetUnusedInstances;

+ (void)fontSetWillChangeNotification:(NSNotification *)note;

- initWithFontAttributes:(NSDictionary *)fontAttributes;
- initWithFamily:(NSString *)family size:(CGFloat)size;
- initWithFamily:(NSString *)family size:(CGFloat)size weight:(NSInteger)weight italic:(BOOL)italic condensed:(BOOL)condensed fixedPitch:(BOOL)fixedPitch;
- initWithName:(NSString *)name size:(CGFloat)size; // Used when reading fonts from RTF
- initWithFont:(OAFontDescriptorPlatformFont)font;

- (NSDictionary *)fontAttributes;

// These accessors return the value stored in the descriptor's attributes dictionary, if present, or else return the attributes of the font obtained by resolving the descriptor.
- (NSString *)family;
- (CGFloat)size;
- (BOOL)hasExplicitWeight;
- (NSInteger)weight;
- (BOOL)valueForTrait:(uint32_t)trait;
- (BOOL)italic;
- (BOOL)bold;
- (BOOL)condensed;
- (BOOL)fixedPitch;
- (NSString *)fontName;
- (NSString *)postscriptName;
- (OAFontDescriptorPlatformFont)font;

// These return the desired values, where as our other properties return calculated values. If a value doesn't have a desired setting, it will return nil.
@property(nonatomic,readonly) NSString *desiredFontName;

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
- (NSString *)localizedStyleName;
#endif

- (OAFontDescriptor *)newFontDescriptorWithFamily:(NSString *)family;
- (OAFontDescriptor *)newFontDescriptorWithSize:(CGFloat)size;
- (OAFontDescriptor *)newFontDescriptorWithWeight:(NSInteger)weight;
- (OAFontDescriptor *)newFontDescriptorWithValue:(BOOL)value forTrait:(uint32_t)trait; // Trait is the CoreText font traits like kCTFontBoldTrait
- (OAFontDescriptor *)newFontDescriptorWithBold:(BOOL)bold;
- (OAFontDescriptor *)newFontDescriptorWithItalic:(BOOL)italic;
- (OAFontDescriptor *)newFontDescriptorWithCondensed:(BOOL)condensed;
- (OAFontDescriptor *)newFontDescriptorWithFixedPitch:(BOOL)fixedPitch;

@end
