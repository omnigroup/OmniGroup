// Copyright 2003-2011 Omni Development, Inc. All rights reserved.
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
// On iPhone, there is no class to bridge to.  So, this class is currently a wrapper of a CTFontDescriptorRef instead of a subclass/replacement for NSFontDescriptor.

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
    #import <CoreText/CTFont.h>
    #import <CoreText/CTFontDescriptor.h>
    #define OAFontDescriptorPlatformFont CTFontRef
#else
    #import <ApplicationServices/ApplicationServices.h> // CoreText lives in this umbrella on the Mac
    @class NSFont;
    #define OAFontDescriptorPlatformFont NSFont *
#endif

@class NSNotification, NSDictionary;

extern CGFloat OAFontDescriptorDefaultFontWeight(void);
extern OFExtent OAFontDescriptorValidFontWeightExtent(void);

@interface OAFontDescriptor : OFObject <NSCopying>
{
@private
    NSDictionary *_attributes;
    CTFontDescriptorRef _fontDescriptor;
    OAFontDescriptorPlatformFont _font;
    BOOL _isUniquedInstance;
}

+ (void)forgetUnusedInstances;

+ (void)fontSetWillChangeNotification:(NSNotification *)note;

- initWithFontAttributes:(NSDictionary *)fontAttributes;
- initWithFamily:(NSString *)family size:(CGFloat)size;
- initWithFamily:(NSString *)family size:(CGFloat)size weight:(NSInteger)weight italic:(BOOL)italic condensed:(BOOL)condensed fixedPitch:(BOOL)fixedPitch;
- initWithFont:(OAFontDescriptorPlatformFont)font;

- (NSDictionary *)fontAttributes;
- (NSString *)family;
- (CGFloat)size;
- (NSInteger)weight;
- (BOOL)valueForTrait:(uint32_t)trait;
- (BOOL)italic;
- (BOOL)bold;
- (BOOL)condensed;
- (BOOL)fixedPitch;
- (NSString *)fontName;
- (NSString *)postscriptName;
- (OAFontDescriptorPlatformFont)font;

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

- (NSDictionary *)matchedAttributes;

@end
