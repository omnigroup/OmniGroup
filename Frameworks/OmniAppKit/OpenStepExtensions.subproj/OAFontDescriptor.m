// Copyright 2003-2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OAFontDescriptor.h>

#import <OmniFoundation/OFCFCallbacks.h>
#import <OmniFoundation/NSNumber-OFExtensions-CGTypes.h>
#import <OmniFoundation/NSString-OFSimpleMatching.h>
#import <OmniBase/OmniBase.h>

#import <Foundation/Foundation.h>

RCS_ID("$Id$");

#if 0 && defined(DEBUG_curt) && defined(DEBUG)
#define DEBUG_FONT_LOOKUP(format, ...) NSLog(@"FONT_LOOKUP: " format, ## __VA_ARGS__)
#else
#define DEBUG_FONT_LOOKUP(format, ...)
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

NSDictionary *attributesFromFont(OAFontDescriptorPlatformFont font)
{
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
    OBPRECONDITION(font != NULL);
    CTFontRef coreTextFont = font;
    CTFontDescriptorRef fontDescriptor = CTFontCopyFontDescriptor(coreTextFont);
    CFDictionaryRef fontAttributes = CTFontDescriptorCopyAttributes(fontDescriptor);
    NSDictionary *result = (NSDictionary *)CFDictionaryCreateCopy(NULL, fontAttributes);
    CFRelease(fontAttributes);
    CFRelease(fontDescriptor);
    return [result autorelease];
#else
    OBPRECONDITION(font != nil);
    NSFont *macFont = font;
    return macFont.fontDescriptor.fontAttributes;
#endif
}

// CoreText's font traits are often normalize -1..1 where AppKits are BOOL or an int with defined values. To avoid lossy round-tripping this function and the next should be inverses of each other over the integers [1,14].
static CGFloat _fontManagerWeightToWeight(NSInteger weight)
{
    // Defined as three linear functions over distinct ranges to approximate the previous discretation approach.
    if (weight < 5)
        return 0.25 * (weight - 5.0);
    else if (weight < 9)
        return 0.3 * 0.25 * (weight - 5.0);
    else
        return 0.7 * 0.20 * (weight - 9.0) + 0.3;
}

static NSInteger _weightToFontManagerWeight(CGFloat weight)
{
    // Defined as three linear functions over distinct ranges to approximate the previous discretation approach.
    // -1.0 |==> 1
    //  0.0 |==> 5, "regular"
    //  0.3 |==> 9, "bold"
    //  1.0 |==> 14, "extra black"
    if (weight < 0)
        return floor(4.0 * (weight + 1.0) + 1.0);
    else if (weight < 0.3)
        return floor(4.0 * weight / 0.3 + 5.0);
    else
        return floor(5 * (weight - 0.3) / 0.7 + 9.0);
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

- initWithFontAttributes:(NSDictionary *)fontAttributes;
{
    OBPRECONDITION(fontAttributes);
    OBPRECONDITION(fontAttributes[(id)kCTFontWeightTrait] == nil, @"Font weight trait should be set in the traits subdictionary, not on the top-level attributes");
    
    if (!(self = [super init]))
        return nil;
    
    _attributes = [fontAttributes copy];
    
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

// <bug://bugs/60459> ((Re) add support for expanded/condensed/width in OSFontDescriptor): add 'expanded' or remove 'condensed' and replace with 'width'. This would be a backwards compatibility issue w.r.t. archiving, though.
// This (currently) takes the NSFontManager-style weight, or 0 for no explicit weight. Longer term, we should just switch to archiving a plist with the entire font descriptor, maybe.  Or maybe we should just switch to archiving the 0..1 weight and width attributes.
- initWithFamily:(NSString *)family size:(CGFloat)size weight:(NSInteger)weight italic:(BOOL)italic condensed:(BOOL)condensed fixedPitch:(BOOL)fixedPitch;
{
    OBPRECONDITION(![NSString isEmptyString:family]);
    OBPRECONDITION(size > 0.0f);
    
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
    
    self = [self initWithFontAttributes:attributes];
    OBASSERT([self font]); // Make sure we can cache a font
    
    [attributes release];
    return self;
}

- initWithFont:(OAFontDescriptorPlatformFont)font;
{
    OBPRECONDITION(font);

    // Note that this leaves _font as nil so that we get the same results as forward mapping via our caching.
    NSDictionary *attributes;
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
    CTFontDescriptorRef fontDescriptor = CTFontCopyFontDescriptor(font);
    attributes = (NSDictionary *)CTFontDescriptorCopyAttributes(fontDescriptor);
    CFRelease(fontDescriptor);
#else
    attributes = [[font fontDescriptor] fontAttributes];
#endif

    self = [self initWithFontAttributes:attributes];
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
    [attributes release];
#endif
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
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
    if (_font)
        CFRelease(_font);
#else
    [_font release];
#endif
    [_attributes release];
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
    NSString *family = [_attributes objectForKey:(id)kCTFontFamilyNameAttribute];
    if (family)
        return family;
    
    OAFontDescriptorPlatformFont font = self.font;
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
    return [(id)CTFontCopyFamilyName(font) autorelease];
#else
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

- (NSString *)postscriptName
{
    OAFontDescriptorPlatformFont font = self.font;
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
    return [(id)NSMakeCollectable(CTFontCopyPostScriptName(font)) autorelease];
#else
    return [font fontName];
#endif    
}

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
- (NSString *)localizedStyleName;
{
    CFStringRef styleName = CTFontCopyLocalizedName([self font], kCTFontStyleNameKey, NULL);
    if (styleName)
        return [(id)NSMakeCollectable(styleName) autorelease];
    
    return nil;
}
#endif

- (CGFloat)size;
{
    NSNumber *fontSize = [_attributes objectForKey:(id)kCTFontSizeAttribute];
    if (fontSize)
        return [fontSize cgFloatValue];
    
    
    OAFontDescriptorPlatformFont font = self.font;
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
    return CTFontGetSize(font);
#else
    return [font pointSize];
#endif
}

- (NSNumber *)_coreTextFontWeight; // result may be nil if we don't find an explicit font weight
{
    NSDictionary *traitDictionary = _attributes[(id)kCTFontTraitsAttribute];
    NSNumber *weightNumber = traitDictionary[(id)kCTFontWeightTrait];
    return weightNumber;
}

- (BOOL)hasExplicitWeight;
{
    // Implementation here should match that of -weight in that we return YES if and only if we would take one of the explicit early-outs from that method.
    return [self _coreTextFontWeight] != nil || self.bold;
}

// We return the NSFontManager-style weight here.
- (NSInteger)weight;
{
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

static CTFontSymbolicTraits _symbolicTraits(OAFontDescriptor *self)
{
    NSDictionary *traits = [self->_attributes objectForKey:(id)kCTFontTraitsAttribute];
    NSNumber *symbolicTraitsNumber = [traits objectForKey:(id)kCTFontSymbolicTrait];
    if (symbolicTraitsNumber) {
        OBASSERT(sizeof(CTFontSymbolicTraits) == sizeof(unsigned int));
        return [symbolicTraitsNumber unsignedIntValue];
    }
    
    OAFontDescriptorPlatformFont font = self.font;
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
    return CTFontGetSymbolicTraits(font);
#else
    // NSFontTraitMask is NSUInteger; avoid a warning and assert that we aren't dropping anything by the cast.
    NSFontTraitMask result = [[NSFontManager sharedFontManager] traitsOfFont:font];
    OBASSERT(sizeof(CTFontSymbolicTraits) == sizeof(uint32_t));
    OBASSERT(sizeof(result) == sizeof(uint32_t) || result <= UINT32_MAX);
    return (CTFontSymbolicTraits)result;
#endif
}

// NSFontTraitMask and CTFontSymbolicTraits are the same for italic, bold, narrow and fixed-pitch.  Check others before using this for them.
static BOOL _hasSymbolicTrait(OAFontDescriptor *self, unsigned trait)
{
    CTFontSymbolicTraits traits = _symbolicTraits(self);
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
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE    
    return CTFontCreateWithFontDescriptor(fontDesc, size/*size*/, NULL/*matrix*/);
#else
    return [[NSFont fontWithDescriptor:(NSFontDescriptor *)fontDesc size:size] retain];
#endif
}

static BOOL _isReasonableFontMatch(CTFontDescriptorRef matchingDescriptor, OAFontDescriptorPlatformFont font)
{
    BOOL seemsOK = YES;
    
    // Check font family
    CFStringRef desiredFamilyName = CTFontDescriptorCopyAttribute(matchingDescriptor, kCTFontFamilyNameAttribute);
    NSString *newFontFamilyName = nil;
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
    CFStringRef newFontFamilyNameCF = CTFontCopyFamilyName(font);
    if (newFontFamilyNameCF) {
        newFontFamilyName = [NSString stringWithString:(NSString *)newFontFamilyNameCF];
        CFRelease(newFontFamilyNameCF);
    }
#else
    newFontFamilyName = [font familyName];
#endif
    
    if (desiredFamilyName && ![(NSString *)desiredFamilyName isEqualToString:newFontFamilyName]) {
        DEBUG_FONT_LOOKUP(@"Font family name mismatch. Asked for %@, got %@", (id)desiredFamilyName, newFontFamilyName);
        seemsOK = NO;
    }
    
    if (desiredFamilyName)
        CFRelease(desiredFamilyName);
    
    if (! seemsOK)
        return seemsOK; // early out since we already dislike the font
    
    // Check boldness
    CFDictionaryRef traits = CTFontDescriptorCopyAttribute(matchingDescriptor, kCTFontTraitsAttribute);
    NSNumber *symbolicTraitsNumber = [(NSDictionary *)traits objectForKey:(id)kCTFontSymbolicTrait];
    BOOL wantBold = ([symbolicTraitsNumber unsignedIntValue] & kCTFontTraitBold) != 0;
    if (! wantBold) {
        NSNumber *weight = [(NSDictionary *)traits objectForKey:(id)kCTFontWeightTrait];
        wantBold = [weight cgFloatValue] >= _fontManagerWeightToWeight(OAFontDescriptorBoldFontWeight());
    }
    if (traits)
        CFRelease(traits);
    
    BOOL newFontIsBold = NO;
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
    newFontIsBold = (CTFontGetSymbolicTraits(font) & kCTFontTraitBold) != 0;
    if (! newFontIsBold) {
        CFStringRef fontName = CTFontCopyFullName(font);
        newFontIsBold = [(NSString *)fontName containsString:@"bold" options:NSCaseInsensitiveSearch];
        CFRelease(fontName);
    }
#else
    NSFontTraitMask fontTraitMask = [[NSFontManager sharedFontManager] traitsOfFont:font];
    newFontIsBold = (fontTraitMask & NSBoldFontMask) != 0;
    newFontIsBold |= [[font fontName] containsString:@"bold" options:NSCaseInsensitiveSearch];
#endif
    
    if (wantBold != newFontIsBold) {
        DEBUG_FONT_LOOKUP(@"Font boldness mismatch. %@", wantBold ? @"Wanted bold." : @"Wanted not bold.");
        seemsOK = NO;
    }
    
    return seemsOK;
}

- (BOOL)_setFontFromAttributes:(NSDictionary *)attributes size:(CGFloat)size;
{
    CTFontDescriptorRef matchingDescriptor = CTFontDescriptorCreateWithAttributes((CFDictionaryRef)attributes);
    DEBUG_FONT_LOOKUP(@"Trying:\nattributes = %@\nsize = %lf\nmatchingDescriptor = %@", attributes, size, (id)matchingDescriptor);
    if (matchingDescriptor == NULL)
        return NO;
    
    OAFontDescriptorPlatformFont font = _copyFont(matchingDescriptor, size);
    if (! font) {
        DEBUG_FONT_LOOKUP(@"No font found");
        CFRelease(matchingDescriptor);
        return NO;
    }
    
    BOOL reasonableMatch = _isReasonableFontMatch(matchingDescriptor, font);
    CFRelease(matchingDescriptor);

    if (reasonableMatch) {
        _font = font;
    } else {
        DEBUG_FONT_LOOKUP(@"Font not reasonable");
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
        CFRelease(font);
#else
        [font release];
#endif
    }

    return reasonableMatch;
}

- (OAFontDescriptorPlatformFont)font;
{
    // See units tests for font look up in OAFontDescriptorTests. Font lookup is fragile and has different pitfalls on iOS and Mac. Run the unit tests on both platforms.
    
    static NSArray *attributesToRemoveForFallback;
    static NSDictionary *fallbackAttributesDictionary;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // In OO3's version of this we'd prefer traits to the family. Continue doing so here. We don't have support for maintaining serif-ness, though. We remove the size attribute first, but pass the rounded value of it as an additional parameter to _copyFont.
        // CONSIDER: rather than just removing all the traits for our last attempt, we might want to narrow them down in some order.
        attributesToRemoveForFallback = @[(id)kCTFontSizeAttribute, (id)kCTFontNameAttribute, (id)kCTFontFamilyNameAttribute, (id)kCTFontTraitsAttribute];
        [attributesToRemoveForFallback retain];
        fallbackAttributesDictionary = @{(id)kCTFontFamilyNameAttribute: @"Helvetica"};
        [fallbackAttributesDictionary retain];
    });
    
    if (!_font) {
        DEBUG_FONT_LOOKUP(@"-----------------------------------------------------------------------------");
        DEBUG_FONT_LOOKUP(@"Using unadulterated attributes");
        if ([self _setFontFromAttributes:_attributes size:0])
            goto matchSucceeded;

        // No direct match -- most likely the traits produce something w/o an exact match (asking for a bold variant of something w/o bold). We'll progressively clean up the attributes until we get something useful.
        
        // Font weight trait seems particularly vexing. We can fall back on the symbolic bold trait, so let's try again by removing just the weight trait if any.
        NSMutableDictionary *attributeSubset = [NSMutableDictionary dictionaryWithDictionary:_attributes];
        NSDictionary *traits = _attributes[(id)kCTFontTraitsAttribute];
        if (traits && traits[(id)kCTFontWeightTrait] != nil ) {
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
            if ([self _setFontFromAttributes:attributeSubset size:0])
                goto matchSucceeded;
        }
        
        // A non-integral size can annoy font lookup. Let's calculate an integral size to use for remaining attempts. First attribute removed below should be font size.
        CGFloat size = [[_attributes objectForKey:(id)kCTFontSizeAttribute] cgFloatValue];
        CGFloat integralSize = rint(size);
        
        for (NSString *attributeToRemove in attributesToRemoveForFallback) {
            if (attributeSubset[attributeToRemove] == nil)
                continue; // no value to remove
            [attributeSubset removeObjectForKey:attributeToRemove];
            DEBUG_FONT_LOOKUP(@"Removed %@ attribute:", attributeToRemove);
            if ([self _setFontFromAttributes:attributeSubset size:integralSize])
                goto matchSucceeded;
        }
        
        DEBUG_FONT_LOOKUP(@"falling through");
        CTFontDescriptorRef fallbackDescriptor = CTFontDescriptorCreateWithAttributes((CFDictionaryRef)fallbackAttributesDictionary);
        if (fallbackDescriptor != NULL) {
            _font = _copyFont(fallbackDescriptor, integralSize);
            CFRelease(fallbackDescriptor);
        }
        
    matchSucceeded:
        OBASSERT(_font);
        DEBUG_FONT_LOOKUP(@"Matched with attributes:%@", attributesFromFont(_font));
    }
    
    return _font;
}

static OAFontDescriptor *_newWithFontDescriptorHavingTrait(OAFontDescriptor *self, uint32_t trait, BOOL value)
{
    OBPRECONDITION(trait != kCTFontBoldTrait, @"Don't set/clear the bold trait without also updating kCTFontWeightTrait. See -[OAFontDescriptor newFontDescriptorWithWeight:].");
    CTFontSymbolicTraits oldTraits = _symbolicTraits(self);
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
    if (weight == self.weight && self.hasExplicitWeight)
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
    CTFontSymbolicTraits newSymbolicTraits = _symbolicTraits(fontDescriptor);
    
    // We insert the family name of the existing font into the attributes of the new font descriptor. This deals with situations like going from Helvetica-Bold to regular Helvetica. We need the family name, Helvetica, or we will fail to find a regular weight version of the font named Helvetica-Bold.
    [newAttributes setObject:[fontDescriptor family] forKey:(id)kCTFontFamilyNameAttribute];
    
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
    
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
    if (_font) {
        CFRelease(_font);
        _font = NULL;
    }
#else
    [_font release];
    _font = nil;
#endif
}

@end
