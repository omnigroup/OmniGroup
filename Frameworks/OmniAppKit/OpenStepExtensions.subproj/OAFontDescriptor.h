// Copyright 2003-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/OFObject.h>
#import <OmniFoundation/OFExtent.h>
#import <Availability.h>

extern NSInteger OAFontDescriptorRegularFontWeight(void); // NSFontManager-style weight
extern NSInteger OAFontDescriptorBoldFontWeight(void); // NSFontManager-style weight
extern OFExtent OAFontDescriptorValidFontWeightExtent(void);

// On the Mac, NSFontDescriptor is toll-free bridged to CTFontDescriptorRef. NSFont doesn't seem to be bridged, but presumably each platform returns the appropriate font type.
// OBFinishPorting: <bug:///147888> (Frameworks-iOS Engineering: Consider bridging to UIFontDescriptor, maybe)
// On iPhone, there is no class to bridge to. (Update 15 Aug. 2017: now there is: UIFontDescriptor.) So, this class is currently a wrapper of a CTFontDescriptorRef instead of a subclass/replacement for NSFontDescriptor.

#if OMNI_BUILDING_FOR_IOS
    #define OAPlatformFontClass UIFont
    #import <UIKit/UIFont.h>
#elif OMNI_BUILDING_FOR_MAC
    #import <ApplicationServices/ApplicationServices.h> // CoreText lives in this umbrella on the Mac
    #import <AppKit/NSFont.h>
    #define OAPlatformFontClass NSFont
#endif


#ifdef OAPlatformFontClass

typedef OAPlatformFontClass *OAFontDescriptorPlatformFont;
@class OAPlatformFontClass;

@class NSNotification, NSDictionary;

// Returns the _minimal_ set of attributes (on iOS at least). Primarily useful for testing and debugging.
extern NSDictionary *OAAttributesFromFont(OAFontDescriptorPlatformFont font);

@interface OAFontDescriptor : OFObject <NSCopying>

+ (void)forgetUnusedInstances;

+ (void)fontSetWillChangeNotification:(NSNotification *)note;

- initWithFontAttributes:(NSDictionary *)fontAttributes;
- initWithFamily:(NSString *)family size:(CGFloat)size;
- initWithFamily:(NSString *)family size:(CGFloat)size weight:(NSInteger)weight italic:(BOOL)italic condensed:(BOOL)condensed fixedPitch:(BOOL)fixedPitch;
- initWithName:(NSString *)name size:(CGFloat)size; // Used when reading fonts from RTF
- initWithFont:(OAFontDescriptorPlatformFont)font;

@property(nonatomic,readonly) NSDictionary *fontAttributes;

// These accessors return the value stored in the descriptor's attributes dictionary, if present, or else return the attributes of the font obtained by resolving the descriptor.
@property(nonatomic,readonly) NSString *family;
@property(nonatomic,readonly) CGFloat size;
@property(nonatomic,readonly) BOOL hasExplicitWeight;
@property(nonatomic,readonly) NSInteger weight;
- (BOOL)valueForTrait:(uint32_t)trait;
@property(nonatomic,readonly) BOOL italic;
@property(nonatomic,readonly) BOOL bold;
@property(nonatomic,readonly) BOOL condensed;
@property(nonatomic,readonly) BOOL fixedPitch;
@property(nonatomic,readonly) NSString *fontName;
@property(nonatomic,readonly) NSString *postscriptName;
@property(nonatomic,readonly) OAFontDescriptorPlatformFont font;

// These return the desired values, where as our other properties return calculated values. If a value doesn't have a desired setting, it will return nil.
@property(nonatomic,readonly) NSString *desiredFontName;

#if OMNI_BUILDING_FOR_IOS
@property(nonatomic,readonly) NSString *localizedStyleName;
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

#else // OAPlatformFontClass

// Otherwise, we define a simple value class.
@interface OAFontDescriptor : OFObject <NSCopying>

- initWithFamily:(NSString *)family size:(CGFloat)size weight:(NSInteger)weight italic:(BOOL)italic condensed:(BOOL)condensed fixedPitch:(BOOL)fixedPitch;

@property(nonatomic,readonly) NSString *family;
@property(nonatomic,readonly) CGFloat size;
@property(nonatomic,readonly) NSInteger weight;
@property(nonatomic,readonly) BOOL italic;
@property(nonatomic,readonly) BOOL bold;
@property(nonatomic,readonly) BOOL condensed;
@property(nonatomic,readonly) BOOL fixedPitch;

@property(nonatomic,readonly) BOOL hasExplicitWeight;
@property(nonatomic,readonly) NSString *desiredFontName;

@end

#endif // OAPlatformFontClass
