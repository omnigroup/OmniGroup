// Copyright 2003-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OAParagraphStyle.h>

#if OMNI_BUILDING_FOR_IOS || OMNI_BUILDING_FOR_MAC

    // Use the built-in types

#else

#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OFEnumNameTable.h>
#import <OmniFoundation/NSNumber-OFExtensions-CGTypes.h>
#import <Foundation/NSArray.h>
#import <Foundation/NSCharacterSet.h>
#import <Foundation/NSDictionary.h>
#import <Foundation/NSLocale.h>
#import <CoreText/CTParagraphStyle.h>

RCS_ID("$Id$");

NSString * const OATabColumnTerminatorsAttributeName = @"NSTabColumnTerminatorsAttributeName";

@implementation OATextTab

- (id)initWithTextAlignment:(OATextAlignment)alignment location:(CGFloat)location options:(NSDictionary *)options;
{
    OBPRECONDITION(options == nil || ([options count] == 1 && [[options objectForKey:OATabColumnTerminatorsAttributeName] isKindOfClass:[NSCharacterSet class]]));
    
    if (!(self = [super init]))
        return nil;
    
    _alignment = alignment;
    _location = location;
    _options = [options copy];
    
    return self;
}

- (NSDictionary *)options;
{
    return _options;
}

- (id)initWithType:(OATextTabType)type location:(CGFloat)location;
{
    OATextAlignment alignment;
    NSDictionary *options = nil;
    
    switch (type) {
        case OALeftTabStopType:
            alignment = OATextAlignmentLeft;
            break;
        case OARightTabStopType:
            alignment = OATextAlignmentRight;
            break;
        case OACenterTabStopType:
            alignment = OATextAlignmentCenter;
            break;
        case OADecimalTabStopType: {
            alignment = OATextAlignmentRight;

            // TODO: How does NSTextTab deal with the locale for the decimal separator? What happens if the user switches locales or wants to display some data in one locale and other data in another?
            NSString *decimalSeparator = [[NSLocale currentLocale] objectForKey:NSLocaleDecimalSeparator];
            options = [NSDictionary dictionaryWithObject:[NSCharacterSet characterSetWithCharactersInString:decimalSeparator] forKey:OATabColumnTerminatorsAttributeName];
            break;
        }
        default:
            OBASSERT_NOT_REACHED("Unknown text tab type");
            alignment = OATextAlignmentLeft;
            break;
    }
        
    return [self initWithTextAlignment:alignment location:location options:options];
}

- (CGFloat)location;
{
    return _location;
}

- (OATextTabType)tabStopType;
{
    NSCharacterSet *terminators = [_options objectForKey:OATabColumnTerminatorsAttributeName];
    
    if (terminators && _alignment == OATextAlignmentRight) {
        return OADecimalTabStopType;
    }
    
    switch (_alignment) {
        case OATextAlignmentLeft: return OALeftTabStopType;
        case OATextAlignmentRight: return OARightTabStopType;
        case OATextAlignmentCenter: return OACenterTabStopType;
        case OATextAlignmentJustified: return OALeftTabStopType;
        case OATextAlignmentNatural: {
            OBASSERT_NOT_REACHED("Need to look up the default writing direction");
            return OALeftTabStopType;
        }
            
        default:
            OBASSERT_NOT_REACHED("Unknown alignemnt");
            return OATextAlignmentLeft;
    }
}

- (OATextAlignment)alignment;
{
    return _alignment;
}

@end

@implementation OAParagraphStyle

+ (OAParagraphStyle *)defaultParagraphStyle;
{
    static OAParagraphStyle *defaultInstance = nil;
    if (!defaultInstance)
        defaultInstance = [[OAParagraphStyle alloc] init];
    return defaultInstance;
}

- init;
{
    if (!(self = [super init]))
        return nil;
    
    // Defaults based off NSParagraphStyle. Many are zero, but being explicit here to show 
    _scalar.lineSpacing = 0.0f;
    _scalar.paragraphSpacing = 0.0f;
    _scalar.alignment = OATextAlignmentNatural;
    
    _scalar.headIndent = 0.0f;
    _scalar.tailIndent = 0.0f;
    _scalar.firstLineHeadIndent = 0.0f;
    
    _scalar.minimumLineHeight = 0.0f;
    _scalar.maximumLineHeight = 0.0f;
    
    _scalar.baseWritingDirection = OAWritingDirectionLeftToRight;
    _scalar.lineHeightMultiple = 0.0f;
    _scalar.paragraphSpacingBefore = 0.0f;
    _scalar.defaultTabInterval = 0.0f;
    
    static NSArray *defaultStops = nil;
    if (!defaultStops) {
        CGFloat locations[] = {28, 56, 84, 112, 140, 168, 196, 224, 252, 280, 308, 336, -1};

        NSMutableArray *stops = [[NSMutableArray alloc] init];
        
        for (NSUInteger locationIndex = 0; locations[locationIndex] > 0; locationIndex++) {
            OATextTab *tab = [[OATextTab alloc] initWithTextAlignment:OATextAlignmentLeft location:locations[locationIndex] options:nil];
            [stops addObject:tab];
        }
        
        defaultStops = [stops copy];
    }
    
    _tabStops = [defaultStops copy];
    
    return self;
}

- (CGFloat)lineSpacing;
{
    return _scalar.lineSpacing;
}

- (CGFloat)paragraphSpacing;
{
    return _scalar.paragraphSpacing;
}

- (OATextAlignment)alignment;
{
    return _scalar.alignment;
}

- (CGFloat)headIndent;
{
    return _scalar.headIndent;
}

- (CGFloat)tailIndent;
{
    return _scalar.tailIndent;
}

- (CGFloat)firstLineHeadIndent;
{
    return _scalar.firstLineHeadIndent;
}

- (NSArray *)tabStops;
{
    return _tabStops;
}

- (CGFloat)minimumLineHeight;
{
    return _scalar.minimumLineHeight;
}

- (CGFloat)maximumLineHeight;
{
    return _scalar.maximumLineHeight;
}

- (OAWritingDirection)baseWritingDirection;
{
    return _scalar.baseWritingDirection;
}

- (CGFloat)lineHeightMultiple;
{
    return _scalar.lineHeightMultiple;
}

- (CGFloat)paragraphSpacingBefore;
{
    return _scalar.paragraphSpacingBefore;
}

- (CGFloat)defaultTabInterval;
{
    return _scalar.defaultTabInterval;
}

- (OALineBreakMode)lineBreakMode;
{
    return _scalar.lineBreakMode;
}

#pragma mark -
#pragma mark NSCopying

- (id)copyWithZone:(NSZone *)zone;
{
    return self;
}

#pragma mark -
#pragma mark NSMutableCopying

- (id)mutableCopyWithZone:(NSZone *)zone;
{
    return [[OAMutableParagraphStyle alloc] initWithParagraphStyle:self];
}

@end

@implementation OAMutableParagraphStyle

+ (OAParagraphStyle *)defaultParagraphStyle;
{
    // Return a mutable instance when sent to the mutable subclass
    return [[super defaultParagraphStyle] mutableCopy];
}

- initWithParagraphStyle:(OAParagraphStyle *)original;
{
    if (!(self = [super init]))
        return nil;
    
    if (original) {
        memcpy(&_scalar, &original->_scalar, sizeof(_scalar));
        _tabStops = [[NSArray alloc] initWithArray:original->_tabStops];
    }
    
    return self;
}

- (void)setLineSpacing:(CGFloat)aFloat;
{
    _scalar.lineSpacing = aFloat;
}

- (void)setParagraphSpacing:(CGFloat)aFloat;
{
    _scalar.paragraphSpacing = aFloat;
}

- (void)setAlignment:(OATextAlignment)alignment;
{
    _scalar.alignment = alignment;
}

- (void)setFirstLineHeadIndent:(CGFloat)aFloat;
{
    _scalar.firstLineHeadIndent = aFloat;
}

- (void)setHeadIndent:(CGFloat)aFloat;
{
    _scalar.headIndent = aFloat;
}

- (void)setTailIndent:(CGFloat)aFloat;
{
    _scalar.tailIndent = aFloat;
}

- (void)setMinimumLineHeight:(CGFloat)aFloat;
{
    _scalar.minimumLineHeight = aFloat;
}

- (void)setMaximumLineHeight:(CGFloat)aFloat;
{
    _scalar.maximumLineHeight = aFloat;
}

- (void)setBaseWritingDirection:(OAWritingDirection)writingDirection;
{
    _scalar.baseWritingDirection = writingDirection;
}

- (void)setLineHeightMultiple:(CGFloat)aFloat;
{
    _scalar.lineHeightMultiple = aFloat;
}

- (void)setParagraphSpacingBefore:(CGFloat)aFloat;
{
    _scalar.paragraphSpacingBefore = aFloat;
}

- (void)setDefaultTabInterval:(CGFloat)aFloat;
{
    _scalar.defaultTabInterval = aFloat;
}

- (void)setTabStops:(NSArray *)tabStops;
{
    if (_tabStops == tabStops)
        return;

    _tabStops = [tabStops copy];
}

- (void)setLineBreakMode:(OALineBreakMode)mode;
{
    _scalar.lineBreakMode = mode;
}
    
@end

#endif
