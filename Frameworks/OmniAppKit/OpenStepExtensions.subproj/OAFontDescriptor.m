// Copyright 2003-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OAFontDescriptor.h>

#import <OmniFoundation/OFCFCallbacks.h>
#import <OmniFoundation/OFNull.h>
#import <OmniFoundation/NSArray-OFExtensions.h>
#import <OmniFoundation/NSNumber-OFExtensions-CGTypes.h>
#import <OmniFoundation/NSSet-OFExtensions.h>
#import <OmniFoundation/NSString-OFSimpleMatching.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OFGeometry.h>

#import <Foundation/Foundation.h>

#if OMNI_BUILDING_FOR_IOS
#import <UIKit/UIFont.h>
#import <CoreText/CoreText.h>
#elif OMNI_BUILDING_FOR_MAC
#import <AppKit/NSFontManager.h>
#endif

RCS_ID("$Id$");

#if 0 && defined(DEBUG)
#define DEBUG_FONT_LOOKUP(format, ...) NSLog(@"FONT_LOOKUP: " format, ## __VA_ARGS__)
#else
#define DEBUG_FONT_LOOKUP(format, ...)
#endif

NSInteger OAFontDescriptorRegularFontWeight(void) // NSFontManager-style weight
{
    return 5;
}

NSInteger OAFontDescriptorBoldFontWeight(void) // NSFontManager-style weight
{
    return 9;
}

OFExtent OAFontDescriptorValidFontWeightExtent(void)
{
    return OFExtentMake(1.0f, 13.0f); // range is inclusive and given as (location,length), so this includes 14
}

#ifdef OAPlatformFontClass

// UIFont and CTFontRef are toll-free bridged on iOS
#if OMNI_BUILDING_FOR_IOS
static inline CTFontRef UIFontToCTFont(UIFont *font)
{
    return (OB_BRIDGE CTFontRef)font;
}
static inline UIFont *UIFontFromCTFont(CTFontRef fontRef)
{
    return (OB_BRIDGE UIFont *)fontRef;
}
#endif

//#define FONT_DESC_STATS
static NSMutableSet *_OAFontDescriptorUniqueTable = nil;
static NSLock *_OAFontDescriptorUniqueTableLock = nil;
static NSMutableArray *_OAFontDescriptorRecentInstances = nil;

typedef void(^OAAttributeMutator)(NSMutableDictionary *attributes, NSMutableDictionary *traits, CTFontSymbolicTraits *symbolicTraitsRef);

@interface OAFontDescriptor (/*Private*/)
@property (nonatomic,readonly) NSDictionary *attributes; // just cover for the ivar to keep clang happy
- (id)initFromFontDescriptor:(OAFontDescriptor *)fontDescriptor mutatingWith:(OAAttributeMutator)mutatorBlock;
- (void)_invalidateCachedFont;
@end

@implementation OAFontDescriptor
{
@private
    NSDictionary *_attributes;
    OAFontDescriptorPlatformFont _font;
    BOOL _isUniquedInstance;

    // These are cached when making a uniqued instance (and are only valid once _isUniquedInstance is set).
    CTFontSymbolicTraits _symbolicTraits;
    CGFloat _size;
    BOOL _hasExplicitWeight;
    NSInteger _weight;
    NSString *_family;
}

+ (void)initialize;
{
    OBINITIALIZE;

    // We want -hash/-isEqual:, but no -retain/-release
    CFSetCallBacks callbacks = OFNSObjectSetCallbacks;
    callbacks.retain  = NULL;
    callbacks.release = NULL;
    _OAFontDescriptorUniqueTable = (NSMutableSet *)CFSetCreateMutable(kCFAllocatorDefault, 0, &callbacks);
    _OAFontDescriptorUniqueTableLock = [[NSLock alloc] init];
    
    // Keep recently created/in-use instances alive until the next call to +forgetUnusedInstances. We could have a timer running to do this periodically, but we also want to do it in response to memory warnings in UIKit and we don't really want a timer waking up every N seconds when there is nothing to do. Hopefully we'll get a memory warning point to hook into on the Mac or we can add a timer there if we need it (or we could call it when a document is closed).
    _OAFontDescriptorRecentInstances = [[NSMutableArray alloc] init];
}

+ (void)forgetUnusedInstances;
{
    NSArray *oldInstances = nil;
    
    [_OAFontDescriptorUniqueTableLock lock];
    oldInstances = _OAFontDescriptorRecentInstances;
    _OAFontDescriptorRecentInstances = nil;
    [_OAFontDescriptorUniqueTableLock unlock];
    
    [oldInstances release]; // -dealloc will clean out the otherwise unused instances
    
    [_OAFontDescriptorUniqueTableLock lock];
    if (_OAFontDescriptorRecentInstances == nil) // another thread called this?
        _OAFontDescriptorRecentInstances = [[NSMutableArray alloc] initWithArray:[_OAFontDescriptorUniqueTable allObjects]];
    [_OAFontDescriptorUniqueTableLock unlock];
}

// This is currently called by the NSNotificationCenter hacks in OmniOutliner.  Horrifying; maybe those hacks should move here, but better yet would be if we didn't need them.
+ (void)fontSetWillChangeNotification:(NSNotification *)note;
{
    // Invalidate the cached fonts in all our font descriptors.  The various live text storages are about to get a -fixFontAttributeInRange: due to this notification (this gets called specially first so that all the font descriptors are primed to recache the right fonts).
    [_OAFontDescriptorUniqueTableLock lock];
    NSArray *allFontDescriptors = [_OAFontDescriptorUniqueTable allObjects];
    [_OAFontDescriptorUniqueTableLock unlock];
    [allFontDescriptors makeObjectsPerformSelector:@selector(_invalidateCachedFont)];
}

// Returns the _minimal_ set of attributes (on iOS at least). Primarily useful for testing and debugging.
NSDictionary *attributesFromFont(OAFontDescriptorPlatformFont font)
{
#if OMNI_BUILDING_FOR_IOS
    OBPRECONDITION(font != NULL);
    CTFontRef coreTextFont = UIFontToCTFont(font);
    CTFontDescriptorRef fontDescriptor = CTFontCopyFontDescriptor(coreTextFont);
    CFDictionaryRef fontAttributes = CTFontDescriptorCopyAttributes(fontDescriptor);
    NSDictionary *result = (NSDictionary *)CFDictionaryCreateCopy(NULL, fontAttributes);
    CFRelease(fontAttributes);
    CFRelease(fontDescriptor);
    return [result autorelease];
#elif OMNI_BUILDING_FOR_MAC
    OBPRECONDITION(font != nil);
    NSFont *macFont = font;
    return macFont.fontDescriptor.fontAttributes;
#endif
}

// CoreText's font traits normalize weights to the range -1..1 where AppKits are BOOL or an int with defined values. To avoid lossy round-tripping this function and the next should be inverses of each other over the integers [1,14]. Empirically, we can't quite achieve that, however. Analyzing font names on iOS 6.1 shows that "ultralight" fonts, which NSFontManager documents as having an AppKit weight of 1, have a CoreText weight of -0.8. At the other extreme, "extrablack" fonts are documented to have an AppKit weight of 14 but have a CoreText weight of 0.8.
static CGFloat _fontManagerWeightToWeight(NSInteger weight)
{
    if (weight == 1)
        return -0.8;
    else if (weight <= 6)
        return 0.2 * weight - 1.0;
    else if (weight < 14)
        return 0.6 *weight / 8.0 - 0.25;
    else
        return 0.8;
}

static NSInteger _weightToFontManagerWeight(CGFloat weight)
{
    // Defined as four linear functions over distinct ranges based on empirical analysis of all the fonts on iOS 6.1. See svn+ssh://source.omnigroup.com/Source/svn/Omni/trunk/Staff/curt/MiscRadars/FontMetricChecks/CoreTextWeightConversions.ograph
    if (weight < -0.8)
        return 1;
    else if (weight <= 0.2)
        return (NSInteger)round(5.0 * weight + 5.0 );
    else if (weight <= 0.8)
        return (NSInteger)round(8.0 * weight / 0.6 + 10.0 / 3.0);
    else
        return 14;
}

// Takes an NSFontManager weight, [1,14].
static void _setWeightInTraitsDictionary(NSMutableDictionary *traits, CTFontSymbolicTraits *symbolicTraitsRef, NSInteger weight)
{
    OBPRECONDITION(traits != nil);
    OBPRECONDITION(symbolicTraitsRef != NULL);
    OBPRECONDITION(weight == 0 || OFExtentContainsValue(OAFontDescriptorValidFontWeightExtent(), weight));

    BOOL wantsExplicitWeight = weight != 0;
    
    if (!weight)
        weight = OAFontDescriptorRegularFontWeight();
    
    if (wantsExplicitWeight && weight >= OAFontDescriptorBoldFontWeight())
        *symbolicTraitsRef = (*symbolicTraitsRef) | kCTFontBoldTrait;
    else
        *symbolicTraitsRef =  (*symbolicTraitsRef) & ~kCTFontBoldTrait;
    
    if (wantsExplicitWeight) {
        CGFloat normalizedWeight = _fontManagerWeightToWeight(weight);
        [traits setObject:[NSNumber numberWithCGFloat:normalizedWeight] forKey:(id)kCTFontWeightTrait];
    }
}

// All initializers should flow through here in order to get caching.
- initWithFontAttributes:(NSDictionary *)fontAttributes;
{
    OBPRECONDITION(fontAttributes);
    OBPRECONDITION(fontAttributes[(id)kCTFontWeightTrait] == nil, @"Font weight trait should be set in the traits subdictionary, not on the top-level attributes");
    
    if (!(self = [super init]))
        return nil;
    
    _attributes = [fontAttributes copy];
    {
        // Sanitize the symbolic traits to omit the class bits
        NSDictionary *traits = [self->_attributes objectForKey:(id)kCTFontTraitsAttribute];
        NSNumber *symbolicTraitsNumber = [traits objectForKey:(id)kCTFontSymbolicTrait];
        CTFontSymbolicTraits symbolicTraits = [symbolicTraitsNumber unsignedIntValue];
        CTFontSymbolicTraits cleanedSymbolicTraits = _clearClassMask(symbolicTraits);
        if (cleanedSymbolicTraits != symbolicTraits) {
            NSMutableDictionary *updatedTraits = [traits mutableCopy];
            OBASSERT(sizeof(CTFontSymbolicTraits) == sizeof(unsigned int));
            updatedTraits[(id)kCTFontSymbolicTrait] = [NSNumber numberWithUnsignedInt:cleanedSymbolicTraits];
            NSMutableDictionary *updatedAttributes = [_attributes mutableCopy];
            updatedAttributes[(id)kCTFontTraitsAttribute] = updatedTraits;
            [updatedTraits release];
            [_attributes release];
            _attributes = [updatedAttributes copy];
            [updatedAttributes release];
        }
    }
    
    [_OAFontDescriptorUniqueTableLock lock];
    OAFontDescriptor *uniquedInstance = [[_OAFontDescriptorUniqueTable member:self] retain];
    if (uniquedInstance == nil) {
        [_OAFontDescriptorUniqueTable addObject:self];
        [_OAFontDescriptorRecentInstances addObject:self];
#if defined(FONT_DESC_STATS)
        NSLog(@"%lu font descriptors ++ added %@", [_OAFontDescriptorUniqueTable count], self);
#endif
    }
    [_OAFontDescriptorUniqueTableLock unlock];

    if (uniquedInstance) {
        [self release];
        return uniquedInstance;
    } else {
        // This looks at the cache we are trying to fill if _isUniquedInstance is set, so do this first.
        _symbolicTraits = _lookupSymbolicTraits(self);
        _hasExplicitWeight = self.hasExplicitWeight;
        _weight = self.weight;
        _family = [self.family copy];
        _size = self.size;

        _isUniquedInstance = YES; // Track that we need to remove ourselves from the table in -dealloc
        return self;
    }
}

- initWithFamily:(NSString *)family size:(CGFloat)size;
{
    NSMutableDictionary *attributes = [[NSMutableDictionary alloc] init];
    if (family)
        [attributes setObject:family forKey:(id)kCTFontFamilyNameAttribute];
    if (size > 0)
        [attributes setObject:[NSNumber numberWithCGFloat:size] forKey:(id)kCTFontSizeAttribute];

    self = [self initWithFontAttributes:attributes];
    OBASSERT([self font]); // Make sure we can cache a font
    
    [attributes release];
    return self;
}

+ (NSMutableDictionary *)_attributesDictionaryForFamily:(NSString *)family size:(CGFloat)size weight:(NSInteger)weight italic:(BOOL)italic condensed:(BOOL)condensed fixedPitch:(BOOL)fixedPitch;
{
    NSMutableDictionary *attributes = [[NSMutableDictionary alloc] init];
    {
        if (family)
            [attributes setObject:family forKey:(id)kCTFontFamilyNameAttribute];
        if (size > 0)
            [attributes setObject:[NSNumber numberWithCGFloat:size] forKey:(id)kCTFontSizeAttribute];
        
        NSMutableDictionary *traits = [[NSMutableDictionary alloc] init];
        CTFontSymbolicTraits symbolicTraits = 0;
        
        _setWeightInTraitsDictionary(traits, &symbolicTraits, weight);
        
        if (fixedPitch)
            symbolicTraits |= kCTFontMonoSpaceTrait;
        
        if (italic)
            symbolicTraits |= kCTFontItalicTrait;
        
        if (condensed) // We don't archive any notion of expanded.
            symbolicTraits |= kCTFontCondensedTrait;
        
        if (symbolicTraits != 0)
            [traits setObject:[NSNumber numberWithUnsignedInt:symbolicTraits] forKey:(id)kCTFontSymbolicTrait];
        
        if ([traits count] > 0)
            [attributes setObject:traits forKey:(id)kCTFontTraitsAttribute];
        [traits release];
    }
    
    return [attributes autorelease];
}

// <bug://bugs/60459> ((Re) add support for expanded/condensed/width in OSFontDescriptor): add 'expanded' or remove 'condensed' and replace with 'width'. This would be a backwards compatibility issue w.r.t. archiving, though.
// This takes the NSFontManager-style weight, or 0 for no explicit weight.
- initWithFamily:(NSString *)family size:(CGFloat)size weight:(NSInteger)weight italic:(BOOL)italic condensed:(BOOL)condensed fixedPitch:(BOOL)fixedPitch;
{
    OBPRECONDITION(![NSString isEmptyString:family]);
    OBPRECONDITION(size > 0.0f);
    
    NSDictionary *attributes = [OAFontDescriptor _attributesDictionaryForFamily:family size:size weight:weight italic:italic condensed:condensed fixedPitch:fixedPitch];
    self = [self initWithFontAttributes:attributes];
    OBASSERT([self font]); // Make sure we can cache a font
    
    return self;
}

- initWithName:(NSString *)name size:(CGFloat)size;
{
    OBPRECONDITION(![NSString isEmptyString:name]);
    OBPRECONDITION(size > 0.0f);

    OAFontDescriptorPlatformFont font = [OAPlatformFontClass fontWithName:name size:size];
    if (font != nil)
        return [self initWithFont:font];
    else
        return [self initWithFontAttributes:@{(id)kCTFontNameAttribute : name, (id)kCTFontSizeAttribute : @(size)}];
}

- initWithFont:(OAFontDescriptorPlatformFont)font;
{
    OBPRECONDITION(font);

    // Note that this leaves _font as nil so that we get the same results as forward mapping via our caching.
#if OMNI_BUILDING_FOR_IOS
    CTFontDescriptorRef fontDescriptorRef = CTFontCopyFontDescriptor(UIFontToCTFont(font));
#elif OMNI_BUILDING_FOR_MAC
    CTFontDescriptorRef fontDescriptorRef = CTFontDescriptorCreateWithNameAndSize((CFStringRef)font.fontName, font.pointSize);
#endif

    NSString *family = (NSString *)CTFontDescriptorCopyAttribute(fontDescriptorRef, kCTFontFamilyNameAttribute);
    NSString *name = (NSString *)CTFontDescriptorCopyAttribute(fontDescriptorRef, kCTFontNameAttribute);
    NSNumber *sizeRef = (NSNumber *)CTFontDescriptorCopyAttribute(fontDescriptorRef, kCTFontSizeAttribute);
    CGFloat size;
    if (sizeRef != nil) {
        size = sizeRef.doubleValue;
    } else {
        OBASSERT_NOT_REACHED("expected to have a size from the font ref");
        size = 12.0;
    }

    NSDictionary *traits = (NSDictionary *)CTFontDescriptorCopyAttribute(fontDescriptorRef, kCTFontTraitsAttribute);
    NSNumber *weightTrait = traits[(id)kCTFontWeightTrait];
    CGFloat coreTextWeight = [weightTrait doubleValue];
    NSInteger fontManagerWeight = _weightToFontManagerWeight(coreTextWeight);

    NSNumber *symbolicTraitsRef = traits[(id)kCTFontSymbolicTrait];
    NSInteger symbolicTraits = symbolicTraitsRef.unsignedIntegerValue;
    BOOL isItalic = (symbolicTraits & kCTFontTraitItalic) != 0;
    BOOL isCondensed = (symbolicTraits & kCTFontTraitCondensed) != 0;
    BOOL isFixedPitch = (symbolicTraits & kCTFontMonoSpaceTrait) != 0;

    NSMutableDictionary *attributes = [OAFontDescriptor _attributesDictionaryForFamily:family size:size weight:fontManagerWeight italic:isItalic condensed:isCondensed fixedPitch:isFixedPitch];
    
    // Try just the basic attributes to see if that resolves to the font we want.
    // <bug:///118208> (Unassigned: Record specific font name in attributes when members of a font family have the same attributes)
    OAFontDescriptor *basic = [[[self class] alloc] initWithFontAttributes:attributes];
    if (OFISEQUAL(basic.font, font)) {
        [self release];
        self = basic;
    } else {
        // Otherwise, insert the specific font name, but keep the symbolic attributes as a backup so that if this descriptor is archived and unarchived later on a machine w/o this font, we'll at least get a similar weight/italic/etc.
        [basic release];
        attributes[(NSString *)kCTFontNameAttribute] = name;
        
        self = [self initWithFontAttributes:attributes];

#ifdef OMNI_ASSERTIONS_ON
#if OMNI_BUILDING_FOR_IOS

        if (!OFISEQUAL(self.font, font)) {
            
            if (!OFISEQUAL(family, self.family) || !OFISEQUAL(name, self.fontName) || size != self.font.pointSize || isItalic != self.italic || isCondensed != self.condensed || isFixedPitch != self.fixedPitch || fontManagerWeight != self.weight) {
                OBASSERT_NOT_REACHED("The incoming font is not equal to self.font.");
            }
            
            OBASSERT(OFFloatEqualToFloatWithAccuracy(self.font.xHeight, font.xHeight, .01), "The incoming font does not have the same xHeight as self.font.");
            
            if (self.font.capHeight != font.capHeight) {
                OBASSERT_NOT_REACHED("The incoming font does not have the same capHeight as self.font.");
            }

        }
#elif OMNI_BUILDING_FOR_MAC
        if (!OFISEQUAL(self.font, font)) {

            // <bug:///118944> (Bug: Frequent assertion failures 'OFISEQUAL(self.font, font)' in OAFontDescriptor.m:363)
            // Sometimes we get fonts that differ just by the spc attribute, which appears to be related to the line height.
            // ".HelveticaNeueDeskInterface-Regular 11.00 pt. P [] (0x600001445700) fobj=0x6080011f0c00, spc=3.11"
            // ".HelveticaNeueDeskInterface-Regular 11.00 pt. P [] (0x60800105b900) fobj=0x6000001ea200, spc=3.41"
            // In one case, the private _defaultLineHeight is 0, and in the other it’s 13.0.
            // These can be compared via -[NSLayoutManager defaultLineHeightForFont:], which will return 13.0 in both cases.

            if (!OFISEQUAL(family, self.family) || !OFISEQUAL(name, self.fontName) || size != self.font.pointSize || isItalic != self.italic || isCondensed != self.condensed || isFixedPitch != self.fixedPitch || fontManagerWeight != self.weight) {
                OBASSERT_NOT_REACHED("The incoming font is not equal to self.font.");
            }

            NSLayoutManager *layoutManager = [[NSLayoutManager alloc] init];
            if ([layoutManager defaultLineHeightForFont:self.font] != [layoutManager defaultLineHeightForFont:font]) {
                OBASSERT_NOT_REACHED("The incoming font does not have the same default line height as self.font.");
            }
            [layoutManager release];
        }
#else
#error Unknown platform
#endif
#endif
    }
    [family release];
    [name release];
    [sizeRef release];
    [traits release];
    CFRelease(fontDescriptorRef);

    return self;
}

- (void)dealloc;
{
    if (_isUniquedInstance) {
        [_OAFontDescriptorUniqueTableLock lock];
        OBASSERT([_OAFontDescriptorUniqueTable member:self] == self);
        [_OAFontDescriptorUniqueTable removeObject:self];
#if defined(FONT_DESC_STATS)
        NSLog(@"%lu font descriptors -- removed %p", [_OAFontDescriptorUniqueTable count], self);
#endif
        [_OAFontDescriptorUniqueTableLock unlock];
    }
#if OMNI_BUILDING_FOR_IOS
    if (_font)
        CFRelease(_font);
#elif OMNI_BUILDING_FOR_MAC
    [_font release];
#else
#error Unknown platform
#endif
    [_attributes release];
    [_family release];

    [super dealloc];
}

- (NSDictionary *)fontAttributes;
{
    return _attributes;
}

//
// All these getters need to look at the desired setting in _attributes and then at the actual matched font otherwise.
//

- (NSString *)family;
{
    if (_isUniquedInstance) {
        return _family;
    }

    NSString *family = [_attributes objectForKey:(id)kCTFontFamilyNameAttribute];
    if (family)
        return family;
    
    OAFontDescriptorPlatformFont font = self.font;
#if OMNI_BUILDING_FOR_IOS
    return [(id)CTFontCopyFamilyName(UIFontToCTFont(font)) autorelease];
#elif OMNI_BUILDING_FOR_MAC
    return [font familyName];
#endif
}

- (NSString *)fontName;
{    
    NSString *fontName = [_attributes objectForKey:(id)kCTFontNameAttribute];
    if (fontName)
        return fontName;
    
    return [self postscriptName];
}

- (NSString *)desiredFontName;
{
    return [_attributes objectForKey:(id)kCTFontNameAttribute];
}

- (NSString *)postscriptName
{
    OAFontDescriptorPlatformFont font = self.font;
#if OMNI_BUILDING_FOR_IOS
    return [(id)NSMakeCollectable(CTFontCopyPostScriptName(UIFontToCTFont(font))) autorelease];
#elif OMNI_BUILDING_FOR_MAC
    return [font fontName];
#endif    
}

#if OMNI_BUILDING_FOR_IOS
- (NSString *)localizedStyleName;
{
    CFStringRef styleName = CTFontCopyLocalizedName(UIFontToCTFont(self.font), kCTFontStyleNameKey, NULL);
    if (styleName)
        return [(id)NSMakeCollectable(styleName) autorelease];
    
    return nil;
}
#endif

- (CGFloat)size;
{
    if (_isUniquedInstance) {
        return _size;
    }

    NSNumber *fontSize = [_attributes objectForKey:(id)kCTFontSizeAttribute];
    if (fontSize)
        return [fontSize cgFloatValue];
    
    
    OAFontDescriptorPlatformFont font = self.font;
    return font.pointSize;
}

- (NSNumber *)_coreTextFontWeight; // result may be nil if we don't find an explicit font weight
{
    NSDictionary *traitDictionary = _attributes[(id)kCTFontTraitsAttribute];
    NSNumber *weightNumber = traitDictionary[(id)kCTFontWeightTrait];
    return weightNumber;
}

- (BOOL)hasExplicitWeight;
{
    if (_isUniquedInstance) {
        return _hasExplicitWeight;
    }

    // Implementation here should match that of -weight in that we return YES if and only if we would take one of the explicit early-outs from that method.
    return [self _coreTextFontWeight] != nil || self.bold;
}

// We return the NSFontManager-style weight here.
- (NSInteger)weight;
{
    if (_isUniquedInstance) {
        return _weight;
    }

    NSNumber *weightNumber = [self _coreTextFontWeight];
        
    if (weightNumber) {
        CGFloat weight = [weightNumber cgFloatValue];
        return _weightToFontManagerWeight(weight);
    }
    
    // This will look at the requested symbolic traits if set, and at the traits on the actual matched font if not (allowing us to get YES for "GillSans-Bold" when the traits keys aren't set.
    if ([self bold])
        return 9;
    
    // Return the "regular" weight implicitly
    return 5;
}

static CTFontSymbolicTraits _clearClassMask(CTFontSymbolicTraits traits)
{
    // clear kCTFontTraitClassMask, see CTFontStylisticClass.
    return traits & ~kCTFontTraitClassMask;
}

static CTFontSymbolicTraits _lookupSymbolicTraits(OAFontDescriptor *self)
{
    if (self->_isUniquedInstance) {
        return self->_symbolicTraits;
    }

    NSDictionary *traits = [self->_attributes objectForKey:(id)kCTFontTraitsAttribute];
    NSNumber *symbolicTraitsNumber = [traits objectForKey:(id)kCTFontSymbolicTrait];
    if (symbolicTraitsNumber) {
        OBASSERT(sizeof(CTFontSymbolicTraits) == sizeof(unsigned int));
        CTFontSymbolicTraits result = [symbolicTraitsNumber unsignedIntValue];
        return _clearClassMask(result);
    }
    
    OAFontDescriptorPlatformFont font = self.font;
#if OMNI_BUILDING_FOR_IOS
    CTFontSymbolicTraits result = CTFontGetSymbolicTraits(UIFontToCTFont(font));
    return _clearClassMask(result);
#elif OMNI_BUILDING_FOR_MAC
    // NSFontTraitMask is NSUInteger; avoid a warning and assert that we aren't dropping anything by the cast.
    NSFontTraitMask result = [[NSFontManager sharedFontManager] traitsOfFont:font];
    OBASSERT(sizeof(CTFontSymbolicTraits) == sizeof(uint32_t));
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wtautological-constant-out-of-range-compare"
    OBASSERT(sizeof(result) == sizeof(uint32_t) || result <= UINT32_MAX);
#pragma clang diagnostic pop
    return (CTFontSymbolicTraits)result;
#endif
}

// NSFontTraitMask and CTFontSymbolicTraits are the same for italic, bold, narrow and fixed-pitch.  Check others before using this for them.
static BOOL _hasSymbolicTrait(OAFontDescriptor *self, unsigned trait)
{
    CTFontSymbolicTraits traits = _lookupSymbolicTraits(self);
    return (traits & trait) != 0;
}

- (BOOL)valueForTrait:(uint32_t)trait;
{
    return _hasSymbolicTrait(self, trait);
}

- (BOOL)italic;
{
    return _hasSymbolicTrait(self, kCTFontItalicTrait);
}

- (BOOL)bold;
{
    return _hasSymbolicTrait(self, kCTFontBoldTrait);
}

- (BOOL)condensed;
{
    return _hasSymbolicTrait(self, kCTFontCondensedTrait);
}

- (BOOL)fixedPitch;
{
    return _hasSymbolicTrait(self, kCTFontMonoSpaceTrait);
}

static OAFontDescriptorPlatformFont _copyFont(CTFontDescriptorRef fontDesc, CGFloat size)
{
#if OMNI_BUILDING_FOR_IOS
    return UIFontFromCTFont(CTFontCreateWithFontDescriptor(fontDesc, size/*size*/, NULL/*matrix*/));
#elif OMNI_BUILDING_FOR_MAC
    return [[NSFont fontWithDescriptor:(NSFontDescriptor *)fontDesc size:size] retain];
#endif
}

// May return NULL if no descriptors match the desired attributes
static CTFontDescriptorRef _bestMatchingDescriptorForAttributes(NSArray *matchedDescriptors, NSDictionary *desiredAttributes) CF_RETURNS_RETAINED;
static CTFontDescriptorRef _bestMatchingDescriptorForAttributes(NSArray *matchedDescriptors, NSDictionary *desiredAttributes)
{
    // Hello there! If you want to know how this big complicated pile of logic is supposed to work, please see <bug:///109028> (Reference: How we resolve font attributes to a font, and how we fallback on unsatisfiable requests).
    
    // If you're _changing_ this logic, be sure to update that bug!
    
    CTFontDescriptorRef bestMatchByWeightOnly = NULL;
    CGFloat bestMatchWeightDifference = CGFLOAT_MAX;
    
    CTFontDescriptorRef bestMatchRespectingExpandedOrCondensed = NULL;
    CGFloat bestMatchWeightDifferenceRespectingExpandedOrCollapsed = CGFLOAT_MAX;
    
    NSString *desiredFamilyName = desiredAttributes[(id)kCTFontFamilyNameAttribute];
    NSString *desiredFontName = desiredAttributes[(id)kCTFontNameAttribute];
    
    NSDictionary *desiredTraits = desiredAttributes[(id)kCTFontTraitsAttribute];
    unsigned int desiredSymbolicTraits = [(NSNumber *)desiredTraits[(id)kCTFontSymbolicTrait] unsignedIntValue];
    CGFloat desiredWeight = [(NSNumber *)desiredTraits[(id)kCTFontWeightTrait] cgFloatValue];
    BOOL hasDesiredWeight = desiredTraits[(id)kCTFontWeightTrait] != nil;
    
    BOOL wantBold = (desiredSymbolicTraits & kCTFontTraitBold) != 0
    || desiredWeight >= _fontManagerWeightToWeight(OAFontDescriptorBoldFontWeight())
    || [desiredFontName containsString:@"bold" options:NSCaseInsensitiveSearch];

    BOOL wantItalic = (desiredSymbolicTraits & kCTFontTraitItalic) != 0 || (desiredFontName ? [desiredFontName containsString:@"italic" options:NSCaseInsensitiveSearch] : [desiredFamilyName containsString:@"italic" options:NSCaseInsensitiveSearch]);
    BOOL wantCondensed = (desiredSymbolicTraits & kCTFontCondensedTrait) != 0 || (desiredFontName ? [desiredFontName containsString:@"condensed" options:NSCaseInsensitiveSearch] : [desiredFamilyName containsString:@"condensed" options:NSCaseInsensitiveSearch]);
    BOOL wantExpanded = (desiredSymbolicTraits & kCTFontExpandedTrait) != 0 || (desiredFontName ? [desiredFontName containsString:@"expanded" options:NSCaseInsensitiveSearch] : [desiredFamilyName containsString:@"expanded" options:NSCaseInsensitiveSearch]);
    // Expanded and condensed are mutually exclusive, but the style inheritance system might try to ask for such a font anyway.

    for (id descriptorObj in matchedDescriptors) {
        CTFontDescriptorRef candidateDescriptor = (CTFontDescriptorRef)descriptorObj;
        
        // Check font family
        NSString *candidateFontFamilyName = [(NSString *)CTFontDescriptorCopyAttribute(candidateDescriptor, kCTFontFamilyNameAttribute) autorelease];
        
        NSString *candidateFontName = [(NSString *)CTFontDescriptorCopyAttribute(candidateDescriptor, kCTFontNameAttribute) autorelease];
        
        if (desiredFamilyName && ![desiredFamilyName isEqualToString:candidateFontFamilyName]) {
            DEBUG_FONT_LOOKUP(@"Font '%@' family name mismatch. Asked for '%@', got '%@'", (id)candidateFontName, (id)desiredFamilyName, candidateFontFamilyName);
            continue; // early out since we already dislike the font
        }
        
        NSDictionary *candidateTraits = [(NSDictionary *)CTFontDescriptorCopyAttribute(candidateDescriptor, kCTFontTraitsAttribute) autorelease];
        unsigned int candidateSymbolicTraits = [(NSNumber *)candidateTraits[(id)kCTFontSymbolicTrait] unsignedIntValue];
        
        // Check boldness
        wantBold |= [candidateFontFamilyName hasPrefix:@"Hiragino"] && [desiredFontName containsString:@"W6" options:NSCaseInsensitiveSearch]; // special case for Hiragino Kaku Gothic, Hiragino Mincho, and Hiragino Sans whose weights aren't "heavy enough" to be considered bold, but whose bold attributes are set

        BOOL newFontIsBold = (candidateSymbolicTraits & kCTFontTraitBold) != 0 || [candidateFontName containsString:@"bold" options:NSCaseInsensitiveSearch];
        // We sometimes have a mismatch in the bold font attribute for the following font families. Zapfino also has the potential for a mismatch with italic.  We do not check for bold or for italic traits when trying to do a match for the following font families.
        BOOL overRideAttributes = [candidateFontFamilyName hasPrefix:@"Arial Rounded"] || [candidateFontFamilyName hasPrefix:@"Bradley Hand"]|| [candidateFontFamilyName hasPrefix:@"Zapf Dingbats"] || [candidateFontFamilyName hasPrefix:@"Zapfino"] || [candidateFontFamilyName hasPrefix:@"DIN Alternate"] || [candidateFontFamilyName hasPrefix:@"DIN Condensed"] || [candidateFontFamilyName hasPrefix:@"Party LET"] || [candidateFontFamilyName hasPrefix:@"Savoye LET"];

        // Don't skip out on bold flag differences if we requested a by-weight match. Our closest weight match might be bold or it might not.
        if (!overRideAttributes && !hasDesiredWeight && wantBold != newFontIsBold) {
            DEBUG_FONT_LOOKUP(@"Font '%@' boldness mismatch. %@", candidateFontName, wantBold ? @"Wanted bold." : @"Wanted not bold.");
            continue;
        }

        // Check italicness
        BOOL newFontIsItalic = (candidateSymbolicTraits & kCTFontTraitItalic) != 0 || [candidateFontName containsString:@"italic" options:NSCaseInsensitiveSearch];

        if (!overRideAttributes && wantItalic != newFontIsItalic) {
            DEBUG_FONT_LOOKUP(@"Font '%@' italicness mismatch. %@", candidateFontName, wantItalic ? @"Wanted italic." : @"Wanted not italic.");
            continue;
        }
        
        // If our attributes don't specify a condensed or expanded font, we will refuse to match one. That way we don't accidentally shunt the user into a condensed variant of a better weight. But if the user _does_ want a condensed or expanded font and we can't find one, we'll fall back to a regular variant with the best matching weight.
        // We'll also fall back to a regular variant if the user wants a font that is both expanded _and_ collapsed. (The style system might generate such a request based on the inheritance chain.)
        BOOL candidateHasCorrectExpandedOrCondensed = YES;
        
        // Check condensedness
        BOOL newFontIsCondensed = (candidateSymbolicTraits & kCTFontCondensedTrait) != 0 || [candidateFontName containsString:@"condensed" options:NSCaseInsensitiveSearch];
        
        if (newFontIsCondensed) {
            if (!wantCondensed) {
                DEBUG_FONT_LOOKUP(@"Font '%@' is condensed, but we're not looking for a condensed font.", candidateFontName);
                continue;
            } else if (wantCondensed && wantExpanded) {
                DEBUG_FONT_LOOKUP(@"Font '%@' is condensed, but since user wants both expanded and collapsed, we're falling back to neither.", candidateFontName);
                continue;
            }
        }
        candidateHasCorrectExpandedOrCondensed = (wantCondensed == newFontIsCondensed);
        
        // Check expandedness
        BOOL newFontIsExpanded = (candidateSymbolicTraits & kCTFontExpandedTrait) != 0 || [desiredFontName containsString:@"expanded" options:NSCaseInsensitiveSearch];
        
        if (newFontIsExpanded) {
            if (!wantExpanded && ![candidateFontFamilyName hasPrefix:@"Bradley Hand"]) { // Bradley Hand changed to indicate itself as expanded in 8.3, but we don't round-trip it well. this is a similar situation as the pile of fonts excluded by the overRideAttributes flag above.
                DEBUG_FONT_LOOKUP(@"Font '%@' is expanded, but we're not looking for an expanded font.", candidateFontName);
                continue;
            } else if (wantCondensed && wantExpanded) {
                DEBUG_FONT_LOOKUP(@"Font '%@' is expanded, but since user wants both expanded and collapsed, we're falling back to neither.", candidateFontName);
                continue;
            }
        }
        candidateHasCorrectExpandedOrCondensed &= wantExpanded == newFontIsExpanded;
        
        // Check whether the previous best match was closer in weight to our desired weight
        // Do this after checking for both italicness that way we don't accidentally match against an italic font that has a closer weight to the non-italic font we desire
        CGFloat candidateWeight = [(NSNumber *)candidateTraits[(id)kCTFontWeightTrait] cgFloatValue];
        CGFloat weightDifference = fabs(candidateWeight - desiredWeight);
        if (weightDifference < bestMatchWeightDifference) {
            DEBUG_FONT_LOOKUP(@"Font '%@' has weight %f, which is closer to goal weight %f than previous match", candidateFontName, candidateWeight, desiredWeight);
            bestMatchByWeightOnly = candidateDescriptor;
            bestMatchWeightDifference = weightDifference;
        } else {
            DEBUG_FONT_LOOKUP(@"Font '%@' has weight %f, which is farther away from goal weight %f than previous match", candidateFontName, candidateWeight, desiredWeight);
        }
        
        if (candidateHasCorrectExpandedOrCondensed && weightDifference < bestMatchWeightDifferenceRespectingExpandedOrCollapsed) {
            DEBUG_FONT_LOOKUP(@"Font '%@' has correct expanded/condensed, and has weight %f, which is closer to goal weight %f than previous match of correct expanded/condensed", candidateFontName, candidateWeight, desiredWeight);
            bestMatchRespectingExpandedOrCondensed = candidateDescriptor;
            bestMatchWeightDifferenceRespectingExpandedOrCollapsed = weightDifference;
        }
    }
    
    if (bestMatchRespectingExpandedOrCondensed)
        return CFRetain(bestMatchRespectingExpandedOrCondensed);

    if (bestMatchByWeightOnly)
        return CFRetain(bestMatchByWeightOnly);
    
    return NULL;
}

static NSArray *_matchingDescriptorsForFontFamily(NSString *familyName)
{
    static CFSetRef queryMandatoryKeys;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        CFStringRef attributeKeys[] = {kCTFontFamilyNameAttribute};
        queryMandatoryKeys = CFSetCreate(kCFAllocatorDefault, (const void **)attributeKeys, sizeof(attributeKeys)/sizeof(*attributeKeys), &kCFTypeSetCallBacks);
    });
    
    NSDictionary *queryAttributes = @{(id)kCTFontFamilyNameAttribute: familyName};
    CTFontDescriptorRef familyQuery = CTFontDescriptorCreateWithAttributes((CFDictionaryRef)queryAttributes);
    NSArray *matchingDescriptors = (NSArray *)CTFontDescriptorCreateMatchingFontDescriptors(familyQuery, queryMandatoryKeys);
    CFRelease(familyQuery);
    return [matchingDescriptors autorelease];
}

- (OAFontDescriptorPlatformFont)font;
{
    if (_font)
        return _font;
    
    // See units tests for font look up in OAFontDescriptorTests. Font lookup is fragile and has different pitfalls on iOS and Mac. Run the unit tests on both platforms.
    
    static NSArray *attributesToRemoveForFallback;
    static NSDictionary *fallbackAttributesDictionary;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // In OO3's version of this we'd prefer traits to the family. Continue doing so here. We don't have support for maintaining serif-ness, though. We remove the size attribute first, but pass the rounded value of it as an additional parameter to _copyFont.
        // CONSIDER: rather than just removing all the traits for our last attempt, we might want to narrow them down in some order.
        attributesToRemoveForFallback = @[(id)kCTFontSizeAttribute, (id)kCTFontNameAttribute, (id)kCTFontTraitsAttribute];
        [attributesToRemoveForFallback retain];
        fallbackAttributesDictionary = @{(id)kCTFontFamilyNameAttribute: @"Helvetica"};
        [fallbackAttributesDictionary retain];
    });
    
    CGFloat size = [[_attributes objectForKey:(id)kCTFontSizeAttribute] cgFloatValue]; // can be zero; the font system interprets this as "default size", which is 12pt.
    
    // We we want a specific font, try that first. This is important for cases where multiple fonts in the family have the same attributes (Apple Braile, GujaratiMT, etc.).
    CTFontDescriptorRef bestDescriptor;
    NSString *fontName = _attributes[(id)kCTFontNameAttribute];
    if (fontName) {
        bestDescriptor = CTFontDescriptorCreateWithNameAndSize((CFStringRef)fontName, size);
        if (bestDescriptor)
            goto matchSucceeded;
    }
    
    NSString *familyName = _attributes[(id)kCTFontFamilyNameAttribute];
    if (!familyName) {
        // Fonts read from RTF will have a family name if a font is available.  Since it's not, I guess we'll substitute Helvetica.
        familyName = @"Helvetica"; // Try to limp along with a font family we assume exists on all platforms.
    }
    
    NSArray *familyDescriptors = _matchingDescriptorsForFontFamily(familyName);

    DEBUG_FONT_LOOKUP(@"-----------------------------------------------------------------------------");
    DEBUG_FONT_LOOKUP(@"Using unadulterated attributes: %@", _attributes);
    bestDescriptor = _bestMatchingDescriptorForAttributes(familyDescriptors, _attributes);
    if (bestDescriptor)
        goto matchSucceeded;

    // No direct match -- most likely the traits produce something w/o an exact match (asking for a bold variant of something w/o bold). We'll progressively clean up the attributes until we get something useful.
    
    // Try removing the fixed-pitch attribute first. We're hoping that the family name gives us a fall-back for this.
    NSMutableDictionary *attributeSubset = [NSMutableDictionary dictionaryWithDictionary:_attributes];
    NSDictionary *traits = attributeSubset[(id)kCTFontTraitsAttribute];
    NSNumber *symbolicTraitsRef = traits[(id)kCTFontSymbolicTrait];
    CTFontSymbolicTraits symbolicTraits = [symbolicTraitsRef unsignedIntValue];
    if ((symbolicTraits & kCTFontTraitMonoSpace) != 0) {
        symbolicTraits = symbolicTraits & ~kCTFontTraitMonoSpace;
        NSMutableDictionary *replacementTraits = [traits mutableCopy];
        replacementTraits[(id)kCTFontSymbolicTrait] = [NSNumber numberWithUnsignedInt:symbolicTraits];
        attributeSubset[(id)kCTFontTraitsAttribute] = replacementTraits;
        traits = nil; // replacing the traits in the attributes dictionary can release the traits object
        [replacementTraits release];
        DEBUG_FONT_LOOKUP(@"Removing monospace (fixed-width) attribute");
        
        bestDescriptor = _bestMatchingDescriptorForAttributes(familyDescriptors, attributeSubset);
        if (bestDescriptor)
            goto matchSucceeded;
    }
    
    // Font weight trait seems particularly vexing, particularly on iOS where the matching algorithm brooks no weight approximation.
    traits = attributeSubset[(id)kCTFontTraitsAttribute];
    NSNumber *existingWeight = traits[(id)kCTFontWeightTrait];
    if (traits && existingWeight != nil ) {
        // We can fall back on the symbolic bold trait, so let's try again by removing just the weight trait if any.
        if ([traits count] == 1) {
            // weight is the only trait, so remove the traits altogether
            [attributeSubset removeObjectForKey:(id)kCTFontTraitsAttribute];
        } else {
            NSMutableDictionary *traitsSubset = [traits mutableCopy];
            [traitsSubset removeObjectForKey:(id)kCTFontWeightTrait];
            attributeSubset[(id)kCTFontTraitsAttribute] = traitsSubset;
            [traitsSubset release];
        }
        DEBUG_FONT_LOOKUP(@"Removed weight trait");
        bestDescriptor = _bestMatchingDescriptorForAttributes(familyDescriptors, attributeSubset);
        if (bestDescriptor)
            goto matchSucceeded;
    }
    
    // A non-integral size can annoy font lookup. Let's calculate an integral size to use for remaining attempts. First attribute removed below should be font size.
    CGFloat integralSize = rint(size);
    
    for (NSString *attributeToRemove in attributesToRemoveForFallback) {
        if (attributeSubset[attributeToRemove] == nil)
            continue; // no value to remove
        [attributeSubset removeObjectForKey:attributeToRemove];
        DEBUG_FONT_LOOKUP(@"Removed %@ attribute:", attributeToRemove);
        bestDescriptor = _bestMatchingDescriptorForAttributes(familyDescriptors, attributeSubset);
        if (bestDescriptor)
            goto matchSucceeded;
    }
    
    // One last try with just the family name and size
    DEBUG_FONT_LOOKUP(@"Trying with just the family name");
    if (familyName != nil) {
        bestDescriptor = _bestMatchingDescriptorForAttributes(familyDescriptors, @{(id)kCTFontFamilyNameAttribute:familyName});
        if (bestDescriptor)
            goto matchSucceeded;
    }
    
    DEBUG_FONT_LOOKUP(@"falling through");
    CTFontDescriptorRef fallbackDescriptor = CTFontDescriptorCreateWithAttributes((CFDictionaryRef)fallbackAttributesDictionary);
    if (fallbackDescriptor != NULL) {
        _font = _copyFont(fallbackDescriptor, integralSize);
        CFRelease(fallbackDescriptor);
    }

#if OMNI_BUILDING_FOR_MAC
    if (!_font) {
        DEBUG_FONT_LOOKUP(@"Last-ditch attempt — system font of size")
        _font = [NSFont systemFontOfSize:integralSize];
    }
#endif

    goto done;
        
matchSucceeded:
    DEBUG_FONT_LOOKUP(@"Matched to descriptor: %@", bestDescriptor);
    _font = _copyFont(bestDescriptor, size);
    CFRelease(bestDescriptor);
    OBASSERT_NOTNULL(_font);
    
done:
    DEBUG_FONT_LOOKUP(@"Resulting _font: %@", _font);
    DEBUG_FONT_LOOKUP(@"-----------------------------------------------------------------------------");
    return _font;
}

static OAFontDescriptor *_newWithFontDescriptorHavingTrait(OAFontDescriptor *self, uint32_t trait, BOOL value)
{
    OBPRECONDITION(trait != kCTFontBoldTrait, @"Don't set/clear the bold trait without also updating kCTFontWeightTrait. See -[OAFontDescriptor newFontDescriptorWithWeight:].");
    CTFontSymbolicTraits oldTraits = _lookupSymbolicTraits(self);
    CTFontSymbolicTraits newTraits;
    if (value)
        newTraits = oldTraits | trait;
    else
        newTraits = oldTraits & ~trait;
    
    if (newTraits == oldTraits)
        return [self retain];
    
    OAFontDescriptor *result = [[OAFontDescriptor alloc] initFromFontDescriptor:self mutatingWith:^(NSMutableDictionary *attributes, NSMutableDictionary *traits, CTFontSymbolicTraits *symbolicTraitsRef) {
        *symbolicTraitsRef = newTraits;
    }];
    
    return result;
}

// TODO: These should match most strongly on the indicated attribute, but the current code just tosses it in on equal footing with our regular matching rules.
- (OAFontDescriptor *)newFontDescriptorWithFamily:(NSString *)family;
{
    if ([family isEqualToString:self.family])
        return [self retain];
    
    OAFontDescriptor *result = [[OAFontDescriptor alloc] initFromFontDescriptor:self mutatingWith:^(NSMutableDictionary *attributes, NSMutableDictionary *traits, CTFontSymbolicTraits *symbolicTraitsRef) {
        [attributes setObject:family forKey:(id)kCTFontFamilyNameAttribute];

        // remove other names of fonts so that our family choice will win over these.
        [attributes removeObjectForKey:(id)kCTFontNameAttribute];
        [attributes removeObjectForKey:(id)kCTFontDisplayNameAttribute];
        [attributes removeObjectForKey:(id)kCTFontStyleNameAttribute];
    }];
    
    return result;
}

- (OAFontDescriptor *)newFontDescriptorWithSize:(CGFloat)size;
{
    if (size == self.size)
        return [self retain];
    
    OAFontDescriptor *result = [[OAFontDescriptor alloc] initFromFontDescriptor:self mutatingWith:^(NSMutableDictionary *attributes, NSMutableDictionary *traits, CTFontSymbolicTraits *symbolicTraitsRef) {
        [attributes setObject:[NSNumber numberWithDouble:size] forKey:(id)kCTFontSizeAttribute];
    }];
    
    return result;
}

- (OAFontDescriptor *)newFontDescriptorWithWeight:(NSInteger)weight;
{
    if (self.hasExplicitWeight && weight == self.weight)
        return [self retain];
    
    OAFontDescriptor *result = [[OAFontDescriptor alloc] initFromFontDescriptor:self mutatingWith:^(NSMutableDictionary *attributes, NSMutableDictionary *traits, CTFontSymbolicTraits *symbolicTraitsRef) {
        _setWeightInTraitsDictionary(traits, symbolicTraitsRef, weight);
    }];
    
    return result;
}

- (OAFontDescriptor *)newFontDescriptorWithValue:(BOOL)value forTrait:(uint32_t)trait;
{
    OBPRECONDITION(trait != kCTFontBoldTrait, @"Don't set/clear the bold trait without also updating kCTFontWeightTrait. See -[OAFontDescriptor newFontDescriptorWithWeight:].");
    return _newWithFontDescriptorHavingTrait(self, trait, value);
}

- (OAFontDescriptor *)newFontDescriptorWithBold:(BOOL)flag;
{
    return [self newFontDescriptorWithWeight:flag ? OAFontDescriptorBoldFontWeight() : OAFontDescriptorRegularFontWeight()];
}

- (OAFontDescriptor *)newFontDescriptorWithItalic:(BOOL)flag;
{
    return [self newFontDescriptorWithValue:flag forTrait:kCTFontItalicTrait];
}

- (OAFontDescriptor *)newFontDescriptorWithCondensed:(BOOL)flag;
{
    return [self newFontDescriptorWithValue:flag forTrait:kCTFontCondensedTrait];
}

- (OAFontDescriptor *)newFontDescriptorWithFixedPitch:(BOOL)fixedPitch;
{
    return [self newFontDescriptorWithValue:fixedPitch forTrait:kCTFontMonoSpaceTrait];
}

#pragma mark -
#pragma mark Comparison

- (NSUInteger)hash;
{
    return [_attributes hash];
}

- (BOOL)isEqual:(id)otherObject;
{
    if (self == otherObject)
        return YES;
    if (!otherObject)
        return NO;
    if (![otherObject isKindOfClass:[OAFontDescriptor class]])
        return NO;

    OAFontDescriptor *otherDesc = (OAFontDescriptor *)otherObject;
    return [_attributes isEqual:otherDesc->_attributes];
}

#pragma mark -
#pragma mark NSCopying protocol

- (id)copyWithZone:(NSZone *)zone;
{
    return [self retain];
}

#pragma mark -
#pragma mark Debugging

- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *dict = [super debugDictionary];

    [dict setObject:_attributes forKey:@"attributes"];
    if (_font) {
        [dict setObject:(id)_font forKey:@"font"];
        [dict setObject:attributesFromFont(_font) forKey:@"attributesFromFont"];
    }
    return dict;
    
}

#pragma mark -
#pragma mark Private

- (id)initFromFontDescriptor:(OAFontDescriptor *)fontDescriptor mutatingWith:(OAAttributeMutator)mutatorBlock;
{
    OBPRECONDITION(fontDescriptor != nil);
    OBPRECONDITION(fontDescriptor != self); // Avoid some hideous potential aliasing. What kind of monster are you?
    OBPRECONDITION(mutatorBlock != NULL);
    
    [fontDescriptor font]; // Make sure we've cached our descriptor
    
    NSDictionary *traitsDict = [fontDescriptor.attributes objectForKey:(id)kCTFontTraitsAttribute];
    NSMutableDictionary *newTraitsDict = traitsDict ? [traitsDict mutableCopy] : [[NSMutableDictionary alloc] init];
    NSMutableDictionary *newAttributes = [fontDescriptor.attributes mutableCopy];
    [newAttributes setObject:newTraitsDict forKey:(id)kCTFontTraitsAttribute];
    [newTraitsDict release];
    CTFontSymbolicTraits newSymbolicTraits = _lookupSymbolicTraits(fontDescriptor);
    
    // We insert the family name of the existing font into the attributes of the new font descriptor. This deals with situations like going from Helvetica-Bold to regular Helvetica. We need the family name, Helvetica, or we will fail to find a regular weight version of the font named Helvetica-Bold.
    [newAttributes setObject:[fontDescriptor family] forKey:(id)kCTFontFamilyNameAttribute];
    
    // We now need to forget our PostScript name, or else font matching will prefer it over any of the other attributes we've specified
    [newAttributes removeObjectForKey:(id)kCTFontNameAttribute];
    
    if (mutatorBlock != NULL)
        mutatorBlock(newAttributes, newTraitsDict, &newSymbolicTraits);
    
    [newTraitsDict removeObjectForKey:(id)kCTFontSymbolicTrait];
    if (newSymbolicTraits != 0)
        newTraitsDict[(id)kCTFontSymbolicTrait] = [NSNumber numberWithUnsignedInt:newSymbolicTraits];
    
    self = [self initWithFontAttributes:newAttributes];
    [newAttributes release];
    
    return self;
}

- (void)_invalidateCachedFont;
{
    OBPRECONDITION(_isUniquedInstance);
    
#if OMNI_BUILDING_FOR_IOS
    if (_font) {
        CFRelease(_font);
        _font = NULL;
    }
#elif OMNI_BUILDING_FOR_MAC
    [_font release];
    _font = nil;
#else
#error Unknown platform
#endif
}

@end

#else // OAPlatformFontClass

@implementation OAFontDescriptor

- initWithFamily:(NSString *)family size:(CGFloat)size weight:(NSInteger)weight italic:(BOOL)italic condensed:(BOOL)condensed fixedPitch:(BOOL)fixedPitch;
{
    if (!(self = [super init])) {
        return nil;
    }
    
    _family = [family copy];
    _size = size;
    _weight = weight;
    _italic = italic;
    _condensed = condensed;
    _fixedPitch = fixedPitch;
    
    return self;
}

- (void)dealloc;
{
    [_family release];
    [super dealloc];
}

- (NSString *)desiredFontName;
{
    // Maybe we need a completely opaque class for font descriptors and have all the callers know they can't do anything special.
    OBFinishPortingLater("<bug:///147883> (iOS-OmniOutliner Unassigned: -[OAFontDescriptor desiredFontName] - We should maybe have another initializer/setter/something for archiving cases where an explicit font was requested. But then we don't have a way to get the other components)");
    return nil;
}

- (BOOL)hasExplicitWeight;
{
    OBFinishPortingLater("<bug:///147882> (iOS-OmniOutliner Bug: -[OAFontDescriptor hasExplicitWeight] - can we determine this and return other than NO?)");
    return NO;
}

#pragma mark - NSCopying protocol

- (id)copyWithZone:(NSZone *)zone;
{
    return [self retain];
}

@end


#endif // OAPlatformFontClass
