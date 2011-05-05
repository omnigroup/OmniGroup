// Copyright 2010-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUIFontUtilities.h"

#import <OmniUI/OUIInspector.h>
#import <CoreText/CTFont.h>

RCS_ID("$Id$");

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
    NSString *cachedDisplayName = (useFamilyName) ? [familyNameToDisplayName objectForKey:font.familyName] : [fontNameToDisplayName objectForKey:fontName];
    if (cachedDisplayName)
        return cachedDisplayName;
    
    CTFontRef fontRef = CTFontCreateWithName((CFStringRef)fontName, 12.0, NULL);
    if (!fontRef) {
        NSLog(@"No base font ref for %@", font);
        return @"???";
    }
    
    CFStringRef displayName = nil;
    
    if (useFamilyName) 
        displayName = CTFontCopyLocalizedName(fontRef, kCTFontFamilyNameKey, NULL);
    else
        displayName = CTFontCopyDisplayName(fontRef);
    
    CFRelease(fontRef);
    
    OBASSERT(displayName);
    if (!displayName)
        displayName = CFStringCreateCopy(kCFAllocatorDefault, (CFStringRef)font.familyName);
    
    cachedDisplayName = [NSMakeCollectable(displayName) autorelease];
    if (useFamilyName)
        [familyNameToDisplayName setObject:cachedDisplayName forKey:font.familyName];
    else
        [fontNameToDisplayName setObject:cachedDisplayName forKey:fontName];
    
    return cachedDisplayName;
}

NSString *OUIDisplayNameForFontFaceName(NSString *displayName, NSString *baseDisplayName)
{
    OBPRECONDITION([NSThread isMainThread]); // Not thread-safe

    if ([displayName isEqualToString:baseDisplayName])
        return NSLocalizedStringFromTableInBundle(@"Regular", @"OUIInspectors", OMNI_BUNDLE, @"Name for the variant of a font with out any special attributes");
    
    NSMutableString *trimmed = [[displayName mutableCopy] autorelease];
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
        CTFontRef font = CTFontCreateWithName((CFStringRef)fontName, size, NULL/*matrix*/);
        if (!font) {
            OBASSERT_NOT_REACHED("But you gave me the font name!");
            continue;
        }
        
        CTFontSymbolicTraits traits = CTFontGetSymbolicTraits(font);
        CFRelease(font);
        
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

OUIFontSelection OUICollectFontSelection(OUIInspectorSlice *self, id <NSFastEnumeration> objects)
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
        
        if ([fontDescriptorSet member:fontDescriptor] == nil) {
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
    
    return (OUIFontSelection){
        .fontDescriptors = collectedFontDescriptors,
        .fontSizes = collectedFontSizes,
        .fontSizeExtent = OFExtentFromLocations(minFontSize, maxFontSize)
    };
}

