// Copyright 1997-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OAFontCache.h>

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

#import "NSFontManager-OAExtensions.h"

RCS_ID("$Id$")

@interface OAFontCache (Private)
+ (NSDictionary *)generateFontFamilyNameDictionary;
+ (NSDictionary *)canonicalFontFamilyNameDictionary;

static NSUInteger OAFontCacheKeyHash(NSMapTable *table, const void *key);
static BOOL OAFontCacheKeyIsEqual(NSMapTable *table, const void *key1, const void *key2);
@end

typedef struct _OAFontCacheKey {
    NSString *familyName;
    OAFontAttributes attributes;
} OAFontCacheKey;

static NSMapTable *fontMapTable;
static NSLock *fontMapTableLock;
static NSFontManager *fontManager;
static NSDictionary *OAFontFamilySubstitutionDictionary = nil;

@implementation OAFontCache

+ (void)initialize;
{
    NSMapTableKeyCallBacks keyCallBacks;
    
    OBINITIALIZE;

    keyCallBacks.hash = OAFontCacheKeyHash;
    keyCallBacks.isEqual = OAFontCacheKeyIsEqual;
    keyCallBacks.retain = NULL;
    keyCallBacks.release = NULL;
    keyCallBacks.describe = NULL;
    fontMapTable = NSCreateMapTable(keyCallBacks, NSObjectMapValueCallBacks, 32);
    fontMapTableLock = [[NSLock alloc] init];
    fontManager = [[NSFontManager sharedFontManager] retain];
    [[OFController sharedController] addObserver:self];
}

+ (void)controllerDidInitialize:(OFController *)controller;
{
    [self refreshFontSubstitutionDefaults];
}

+ (void)refreshFontSubstitutionDefaults;
{
    [fontMapTableLock lock];
    [OAFontFamilySubstitutionDictionary release];
    OAFontFamilySubstitutionDictionary = [[[NSUserDefaults standardUserDefaults] dictionaryForKey:@"OAFontFamilySubstitutions"] retain];
    [fontMapTableLock unlock];
}

+ (NSString *)fontFamilyMatchingName:(NSString *)fontFamily;
{
    NSDictionary *dictionary;
    NSString *canonicalName;
    NSString *alternateName;
    
    dictionary = [self canonicalFontFamilyNameDictionary];
    if ((canonicalName = [dictionary objectForKey:fontFamily]))
        return canonicalName;
    alternateName = [fontFamily stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if ((canonicalName = [dictionary objectForKey:alternateName]))
        return canonicalName;
    alternateName = [alternateName lowercaseString];
    if ((canonicalName = [dictionary objectForKey:alternateName]))
        return canonicalName;
    alternateName = [alternateName stringByRemovingWhitespace];
    if ((canonicalName = [dictionary objectForKey:alternateName]))
        return canonicalName;
    return nil;
}

+ (NSFont *)fontWithFamily:(NSString *)aFamily attributes:(OAFontAttributes)someAttributes;
{
    NSFont *font;
    OAFontCacheKey lookupKey, *permanentKey;

    [fontMapTableLock lock];
    if (OAFontFamilySubstitutionDictionary != nil) {
        NSString *substituteFontFamily;

        substituteFontFamily = [OAFontFamilySubstitutionDictionary objectForKey:aFamily];
        if (substituteFontFamily != nil)
            aFamily = substituteFontFamily;
    }
    lookupKey.familyName = aFamily;
    lookupKey.attributes = someAttributes;

    font = NSMapGet(fontMapTable, &lookupKey);
    [fontMapTableLock unlock];
    if (font == nil) {
        NSFontTraitMask desiredTraits;

        desiredTraits = 0;
        if (someAttributes.bold)
            desiredTraits |= NSBoldFontMask;
        if (someAttributes.italic)
            desiredTraits |= NSItalicFontMask;
        NS_DURING {
            font = [fontManager fontWithFamily:aFamily traits:desiredTraits weight:5.0 size:someAttributes.size];
            if (font != nil && ([fontManager traitsOfFont:font] & desiredTraits) != desiredTraits)
                font = nil;
        } NS_HANDLER {
            NSLog(@"Warning: Exception calculating font with family %@: %@", aFamily, [localException reason]);
        } NS_ENDHANDLER;
        
        if (font == nil)
            font = [OFNull nullObject];

        [font retain];

        // Create a new entry
        permanentKey = NSZoneMalloc(NULL, sizeof(OAFontCacheKey));
        permanentKey->familyName = [aFamily copy];
        permanentKey->attributes = someAttributes;

        [fontMapTableLock lock];
        NSMapInsert(fontMapTable, permanentKey, font);
        [fontMapTableLock unlock];
    }
                
    return [font isNull] ? nil : font;
}

+ (NSFont *)fontWithFamily:(NSString *)aFamily size:(CGFloat)size bold:(BOOL)boldFlag italic:(BOOL)italicFlag;
{
    OAFontAttributes attributes;

    attributes.size = size;
    attributes.bold = boldFlag;
    attributes.italic = italicFlag;
    return [self fontWithFamily:aFamily attributes:attributes];
}

+ (NSFont *)fontWithFamily:(NSString *)aFamily size:(CGFloat)size;
{
    return [self fontWithFamily:aFamily size:size bold:NO italic:NO];
}

@end

@implementation OAFontCache (Private)

+ (NSDictionary *)generateFontFamilyNameDictionary;
{
    NSDictionary *returnValue;
    NSMutableDictionary *nameDictionary;
    NSArray *availableFontFamilies;
    unsigned int familyIndex, familyCount;

    nameDictionary = [[NSMutableDictionary alloc] init];
    availableFontFamilies = [[NSFontManager sharedFontManager] availableFontFamilies];
    familyCount = [availableFontFamilies count];
    for (familyIndex = 0; familyIndex < familyCount; familyIndex++) {
        NSString *canonicalName;
        NSString *alternateName;

        canonicalName = [availableFontFamilies objectAtIndex:familyIndex];
        [nameDictionary setObject:canonicalName forKey:canonicalName];
        alternateName = [canonicalName lowercaseString];
        if ([nameDictionary objectForKey:alternateName] == nil)
            [nameDictionary setObject:canonicalName forKey:alternateName];
        alternateName = [alternateName stringByRemovingWhitespace];
        if ([nameDictionary objectForKey:alternateName] == nil)
            [nameDictionary setObject:canonicalName forKey:alternateName];
    }
    returnValue = [[NSDictionary alloc] initWithDictionary:nameDictionary];
    [nameDictionary release];
    return [returnValue autorelease];
}

+ (NSDictionary *)canonicalFontFamilyNameDictionary;
{
    static NSDictionary *canonicalFontFamilyNameDictionary = nil;

    if (canonicalFontFamilyNameDictionary != nil)
        return canonicalFontFamilyNameDictionary;

    [NSThread lockMainThread]; // The font machinery may not be thread safe, but more importantly this keeps two threads from calculating the available fonts at the same time
    if (canonicalFontFamilyNameDictionary == nil) { // Someone else might have calculated the dictionary while we were waiting on the lock
        OMNI_POOL_START {
            NS_DURING {
                canonicalFontFamilyNameDictionary = [[self generateFontFamilyNameDictionary] retain];
            } NS_HANDLER {
                NSLog(@"%@: Warning: Exception raised while generating list of available fonts: %@", NSStringFromClass(self), [localException reason]);
            } NS_ENDHANDLER;
        } OMNI_POOL_END;
    }
    [NSThread unlockMainThread];

    return canonicalFontFamilyNameDictionary;
}

static NSUInteger OAFontCacheKeyHash(NSMapTable *table, const void *key)
{
    const OAFontCacheKey *fontCacheKey = (const OAFontCacheKey *)key;

    return [fontCacheKey->familyName hash] +
           ((NSUInteger)(fontCacheKey->attributes.size * 4)) +
           (fontCacheKey->attributes.bold << 1) +
           fontCacheKey->attributes.italic;
}

static BOOL OAFontCacheKeyIsEqual(NSMapTable *table, const void *key1, const void *key2)
{
    const OAFontCacheKey *fontCacheKey1 = (const OAFontCacheKey *)key1;
    const OAFontCacheKey *fontCacheKey2 = (const OAFontCacheKey *)key2;

    if (![fontCacheKey1->familyName isEqualToString:fontCacheKey2->familyName])
        return NO;
    return fontCacheKey1->attributes.size == fontCacheKey2->attributes.size &&
           fontCacheKey1->attributes.bold == fontCacheKey2->attributes.bold &&
           fontCacheKey1->attributes.italic == fontCacheKey2->attributes.italic;
}

@end
