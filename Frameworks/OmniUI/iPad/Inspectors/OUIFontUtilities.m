// Copyright 2010-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIFontUtilities.h>

#import <OmniUI/OUIInspector.h>
#import <CoreText/CTFont.h>

RCS_ID("$Id$");

@implementation OUIFontSelection
@end

// CTFontCreateWithName can end up loading the font off disk, and if this is the only reference, it can do it each time we call this (like when we are reloading in the font family table).
// Cache the display name for each font to avoid this.
NSString *OUIDisplayNameForFont(UIFont *font, BOOL useFamilyName)
{
    OBPRECONDITION([NSThread isMainThread]); // Not thread-safe
    
    if (!font)
        return @"???";
    
    static NSMutableDictionary *fontNameToDisplayName = nil;
    static NSMutableDictionary *familyNameToDisplayName = nil;
    
    if (!fontNameToDisplayName) {
        fontNameToDisplayName = [[NSMutableDictionary alloc] init];
        familyNameToDisplayName = [[NSMutableDictionary alloc] init];
    }
    
    NSString *fontName = font.fontName;
    NSString *cachedDisplayName = useFamilyName ? familyNameToDisplayName[font.familyName] : fontNameToDisplayName[fontName];
    if (cachedDisplayName)
        return cachedDisplayName;
    
    NSString *displayName = nil;
    if (useFamilyName) 
        displayName = CFBridgingRelease(CTFontCopyLocalizedName((OB_BRIDGE CTFontRef)font, kCTFontFamilyNameKey, NULL));
    else
        displayName = CFBridgingRelease(CTFontCopyDisplayName((OB_BRIDGE CTFontRef)font));
    
    OBASSERT(displayName);
    if (!displayName)
        displayName = [font.familyName copy];
    
    if (useFamilyName)
        [familyNameToDisplayName setObject:displayName forKey:font.familyName];
    else
        [fontNameToDisplayName setObject:displayName forKey:fontName];
    
    return displayName;
}

NSString *OUIDisplayNameForFontFaceName(NSString *displayName, NSString *baseDisplayName)
{
    OBPRECONDITION([NSThread isMainThread]); // Not thread-safe

    if ([displayName isEqualToString:baseDisplayName])
        return NSLocalizedStringFromTableInBundle(@"Regular", @"OUIInspectors", OMNI_BUNDLE, @"Name for the variant of a font with out any special attributes");
    
    NSMutableString *trimmed = [displayName mutableCopy];
    [trimmed replaceOccurrencesOfString:baseDisplayName withString:@"" options:0 range:NSMakeRange(0, [trimmed length])];
    [trimmed replaceOccurrencesOfString:@"  " withString:@" " options:0 range:NSMakeRange(0, [trimmed length])]; // In case it was in the middle
    [trimmed replaceOccurrencesOfString:@" " withString:@"" options:NSAnchoredSearch range:NSMakeRange(0, [trimmed length])]; // In case it was at the beginning
    [trimmed replaceOccurrencesOfString:@" " withString:@"" options:NSAnchoredSearch|NSBackwardsSearch range:NSMakeRange(0, [trimmed length])]; // In case it was at the end
    return trimmed;
}

NSString *OUIBaseFontNameForFamilyName(NSString *familyName)
{
    OBPRECONDITION([NSThread isMainThread]); // Not thread-safe

    static NSMutableDictionary *BaseFontNameForFamilyName = nil;
    if (!BaseFontNameForFamilyName)
        BaseFontNameForFamilyName = [[NSMutableDictionary alloc] init];

    NSString *mostNormalFontName = [BaseFontNameForFamilyName objectForKey:familyName];
    if (mostNormalFontName)
        return OFISNULL(mostNormalFontName) ? nil : mostNormalFontName;
    
    // This list of font names is in no particular order and there no good name-based way to determine which is the most normal.
    NSArray *fontNames = [UIFont fontNamesForFamilyName:familyName];
    
    unsigned flagCountForMostNormalFont = UINT_MAX;
    
    CGFloat size = [UIFont labelFontSize];
    for (NSString *fontName in fontNames) {
        UIFont *font = [UIFont fontWithName:fontName size:size];
        if (!font) {
            OBASSERT_NOT_REACHED("But you gave me the font name!");
            continue;
        }
        
        CTFontSymbolicTraits traits = CTFontGetSymbolicTraits((OB_BRIDGE CTFontRef)font);
        
        //traits &= kCTFontClassMaskTrait; // Only count the base traits like bold/italic, not sans serif.
        traits &= 0xffff; // The documentation says the bottom 16 bits are for the symbolic bits.  kCTFontClassMaskTrait is a single bit shifted up, not a mask for the bottom 16 bits.
        
        unsigned flagCount = 0;
        while (traits) {
            if (traits & 0x1)
                flagCount++;
            traits >>= 1;
        }
        
        if (flagCountForMostNormalFont > flagCount) {
            flagCountForMostNormalFont = flagCount;
            mostNormalFontName = fontName;
        }
    }
    
    // Fill the cache
    if (mostNormalFontName)
        [BaseFontNameForFamilyName setObject:mostNormalFontName forKey:familyName];
    else
        [BaseFontNameForFamilyName setObject:[NSNull null] forKey:familyName];
        
    return mostNormalFontName;
}

BOOL OUIIsBaseFontNameForFamily(NSString *fontName, NSString *familyName)
{
    NSString *baseFontName = OUIBaseFontNameForFamilyName(familyName);
    if (OFISNULL(baseFontName))
        return NO;
    return [fontName isEqualToString:baseFontName];
}

OUIFontSelection *OUICollectFontSelection(OUIInspectorSlice *self, id <NSFastEnumeration> objects)
{
    OBPRECONDITION(self);
    
    // Keep things in order, but unique them.
    NSMutableSet *fontDescriptorSet = [NSMutableSet set];
    NSMutableSet *fontSizeSet = [NSMutableSet set];
    
    NSMutableArray *collectedFontDescriptors = [NSMutableArray array];
    NSMutableArray *collectedFontSizes = [NSMutableArray array];
    
    CGFloat minFontSize = 0, maxFontSize = 0;
    
    for (id <OUIFontInspection> object in objects) {
        OAFontDescriptor *fontDescriptor = [object fontDescriptorForInspectorSlice:self];
        OBASSERT(fontDescriptor);

        // we're occasionally crashing attempting to add nil to the data sets below. I'm not sure how we're ever getting into this situation, and have no repro case, but this should guard against it.
        if ([fontDescriptorSet member:fontDescriptor] == nil && fontDescriptor != nil) {
            [fontDescriptorSet addObject:fontDescriptor];
            [collectedFontDescriptors addObject:fontDescriptor];
        }
        
        CGFloat fontSize = [object fontSizeForInspectorSlice:self];
        OBASSERT(fontSize > 0);
        if (fontSize > 0) {
            if (![fontSizeSet count]) {
                minFontSize = maxFontSize = fontSize;
            } else {
                if (minFontSize > fontSize) minFontSize = fontSize;
                if (maxFontSize < fontSize) maxFontSize = fontSize;
            }
            
            NSNumber *fontSizeNumber = [NSNumber numberWithFloat:fontSize];
            if ([fontSizeSet member:fontSizeNumber] == nil) {
                [fontSizeSet addObject:fontSizeNumber];
                [collectedFontSizes addObject:fontSizeNumber];
            }
        }
    }

    OUIFontSelection *result = [OUIFontSelection new];
    result.fontDescriptors = collectedFontDescriptors;
    result.fontSizes = collectedFontSizes;
    result.fontSizeExtent = OFExtentFromLocations(minFontSize, maxFontSize);
    return result;
}

// Radar 15080687: Need API to determine if a font is dynamic type
// This also catches things like +boldSystemFontOfSize
BOOL OUIFontIsDynamicType(UIFont *font)
{
    return [font.fontName hasPrefix:@"."];
}

