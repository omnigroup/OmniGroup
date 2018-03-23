// Copyright 1997-2018 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/NSFont-OAExtensions.h>

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>
#import <ApplicationServices/ApplicationServices.h>

RCS_ID("$Id$")

@implementation NSFont (OAExtensions)

// N.B. These were empirically determined; they may not be stable across OS releases.
static const NSInteger OASystemFontWeightHeavy = 11;
static const NSInteger OASystemFontWeightMedium = 6;
static const NSInteger OASystemFontWeightLight = 3;
static const NSInteger OASystemFontWeightThin = 3;
static const NSInteger OASystemFontWeightUltraLight = 2;

static const NSInteger OASystemFontWeightBoldCutoverWeight = OASystemFontWeightMedium;

+ (NSFont *)OA_systemFontOfSize:(CGFloat)size weight:(NSInteger)weight;
{
    static NSMutableDictionary *fontCache = nil;
    if (fontCache == nil) {
        fontCache = [[NSMutableDictionary alloc] init];
    }
    
    NSString *cacheKey = [NSString stringWithFormat:@"size=%.2f; weight=%ld", size, weight];
    NSFont *cachedResult = fontCache[cacheKey];
    if (cachedResult != nil) {
        return cachedResult;
    }
    
    static NSString *systemFontFamily = nil;
    if (systemFontFamily == nil) {
        NSFont *systemFont = [self systemFontOfSize:[NSFont systemFontSize]];
        systemFontFamily = [systemFont.familyName copy];
    }
    
    NSFont *weightedSystemFont = [[NSFontManager sharedFontManager] fontWithFamily:systemFontFamily traits:0 weight:weight size:size];
    OBASSERT(weightedSystemFont != nil);
    if (weightedSystemFont == nil) {
        if (weight >= OASystemFontWeightBoldCutoverWeight) {
            weightedSystemFont = [NSFont boldSystemFontOfSize:size];
        } else {
            weightedSystemFont = [NSFont systemFontOfSize:size];
        }
    }
    
    fontCache[cacheKey] = weightedSystemFont;
    
    return weightedSystemFont;
}

+ (NSFont *)heavySystemFontOfSize:(CGFloat)size;
{
    return [self OA_systemFontOfSize:size weight:OASystemFontWeightHeavy];
}

+ (NSFont *)mediumSystemFontOfSize:(CGFloat)size;
{
    return [self OA_systemFontOfSize:size weight:OASystemFontWeightMedium];
}

+ (NSFont *)lightSystemFontOfSize:(CGFloat)size;
{
    return [self OA_systemFontOfSize:size weight:OASystemFontWeightLight];
}

+ (NSFont *)thinSystemFontOfSize:(CGFloat)size;
{
    return [self OA_systemFontOfSize:size weight:OASystemFontWeightThin];
}

+ (NSFont *)ultraLightSystemFontOfSize:(CGFloat)size;
{
    return [self OA_systemFontOfSize:size weight:OASystemFontWeightUltraLight];
}

- (BOOL)isScreenFont;
{
    return [self screenFont] == self;
}

+ (NSFont *)fontFromPropertyListRepresentation:(NSDictionary *)dict;
{
    return [NSFont fontWithName:[dict objectForKey:@"name"] size:[[dict objectForKey:@"size"] cgFloatValue]];
}

- (NSDictionary *)propertyListRepresentation;
{
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    [result setObject:[NSNumber numberWithCGFloat:[self pointSize]] forKey:@"size"];
    [result setObject:[self fontName] forKey:@"name"];
    return result;
}

/*" Returns the PANOSE 1 information from the receiver as a string containing ten space-separated decimal numbers. Returns nil if it can't find a PANOSE 1 description of the font.
 
Some PANOSE specification information can be found at http://www.panose.com/ProductsServices/pan1.aspx "*/
- (NSString *)panose1String;
{
    // On 10.5+, NSFont is toll-free-bridged to CTFont
    CTFontRef ctFont = (CTFontRef)self;
    
    // The OS/2 table contains the PANOSE classification
    CFDataRef os2Table = CTFontCopyTable(ctFont, kCTFontTableOS2, kCTFontTableOptionNoOptions /* TODO: kCTFontTableOptionExcludeSynthetic? */ );
    
    if (!os2Table)
        return nil;
    
    // The PANOSE data is in bytes 32-42 of the table according to the TrueType and OpenType specs.
    if (CFDataGetLength(os2Table) < 42) {
        // Truncated table?
        CFRelease(os2Table);
        return nil;
    }
    
    uint8_t panose[10];
    CFDataGetBytes(os2Table, (CFRange){ 32, 10 }, panose);
    
    CFRelease(os2Table);
    
    // Fonts with no PANOSE info but other OS/2 info will usually set this field to all 0s, which is a wildcard specification.
    int i;
    for(i = 0; i < 10; i++)
        if (panose[i] != 0)
            break;
    if (i == 10)
        return nil;

    // Some sanity checks.
    if(panose[0] > 20) {
        // Only 0 through 5 are actually defined by the PANOSE 1 specification.
        // It lists a few other categories but doesn't assign numbers to them. This check should allow for the unlikely event of future expansion of PANOSE 1, while still eliminating completely bogus data.
        return nil;
    }
    
    return [NSString stringWithFormat:@"%d %d %d %d %d %d %d %d %d %d",
            panose[0], panose[1], panose[2], panose[3], panose[4],
            panose[5], panose[6], panose[7], panose[8], panose[9]];
}




@end
