// Copyright 2003-2011 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OAParagraphStyle.h>

#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE

#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OFEnumNameTable.h>
#import <OmniFoundation/NSNumber-OFExtensions-CGTypes.h>
#import <Foundation/NSArray.h>
#import <CoreText/CTParagraphStyle.h>

RCS_ID("$Id$");

@implementation OATextTab

- (id)initWithTextAlignment:(OATextAlignment)alignment location:(CGFloat)location options:(NSDictionary *)options;
{
    OBPRECONDITION(options == nil); // Or we need to add NSTabColumnTerminatorsAttributeName and all that follows
    
    if (!(self = [super init]))
        return nil;
    
    _alignment = alignment;
    _location = location;
    _options = [options copy];
    
    return self;
}

- (void)dealloc;
{
    [_options release];
    [super dealloc];
}

- (NSDictionary *)options;
{
    return _options;
}

- (id)initWithType:(OATextTabType)type location:(CGFloat)location;
{
    OATextAlignment alignment;
    switch (type) {
        case OALeftTabStopType:
            alignment = OALeftTextAlignment;
            break;
        case OARightTabStopType:
            alignment = OARightTextAlignment;
            break;
        case OACenterTabStopType:
            alignment = OACenterTextAlignment;
            break;
        case OADecimalTabStopType:
            OBFinishPorting; // OARightTextAlignment with the decimal character for the user setting
            break;
        default:
            OBASSERT_NOT_REACHED("Unknown text tab type");
            alignment = OALeftTextAlignment;
            break;
    }
        
    return [self initWithTextAlignment:alignment location:location options:nil];
}

- (CGFloat)location;
{
    return _location;
}

- (OATextTabType)tabStopType;
{
    OBPRECONDITION(_options == nil); // Or we need to look this up from options with NSTabColumnTerminatorsAttributeName and all that follows

    NSCharacterSet *terminators = nil;
    
    if (terminators && _alignment == OARightTextAlignment) {
        return OADecimalTabStopType;
    }
    
    switch (_alignment) {
        case OALeftTextAlignment: return OALeftTabStopType;
        case OARightTextAlignment: return OARightTabStopType;
        case OACenterTextAlignment: return OACenterTabStopType;
        case OAJustifiedTextAlignment: return OALeftTabStopType;
        case OANaturalTextAlignment: {
            OBASSERT_NOT_REACHED("Need to look up the default writing direction");
            return OALeftTabStopType;
        }
            
        default:
            OBASSERT_NOT_REACHED("Unknown alignemnt");
            return OALeftTextAlignment;
    }
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
    
    // Defaults based off NSParagraphStyle. Many are the zero, but being explicit here to show 
    _scalar.lineSpacing = 0.0f;
    _scalar.paragraphSpacing = 0.0f;
    _scalar.alignment = OANaturalTextAlignment;
    
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
            OATextTab *tab = [[OATextTab alloc] initWithTextAlignment:OALeftTextAlignment location:locations[locationIndex] options:nil];
            [stops addObject:tab];
            [tab release];
        }
        
        defaultStops = [stops copy];
        [stops release];
    }
    
    _tabStops = [defaultStops copy];
    
    return self;
}

- (void)dealloc;
{
    [_tabStops release];
    [super dealloc];
}

- initWithCTParagraphStyle:(CFTypeRef)ctStyle;
{
    if (!(self = [self init]))
        return nil;
    
    CTParagraphStyleRef style = (CTParagraphStyleRef)ctStyle;
    
    // Note that these default values are the defaults used by CTParagraphStyle, not the ones used by our own style system
#define GET_CGFLOAT(specifier, fieldname, defaultValue) assert(__builtin_types_compatible_p(typeof(_scalar.fieldname), CGFloat)); if (!CTParagraphStyleGetValueForSpecifier(style, specifier, sizeof(CGFloat), &( _scalar.fieldname ))) { _scalar.fieldname = defaultValue; }
    
    GET_CGFLOAT(kCTParagraphStyleSpecifierFirstLineHeadIndent, firstLineHeadIndent, 0.0);
    GET_CGFLOAT(kCTParagraphStyleSpecifierHeadIndent, headIndent, 0.0);
    GET_CGFLOAT(kCTParagraphStyleSpecifierTailIndent, tailIndent, 0.0);
    GET_CGFLOAT(kCTParagraphStyleSpecifierLineSpacing, lineSpacing, 0.0);
    GET_CGFLOAT(kCTParagraphStyleSpecifierParagraphSpacing, paragraphSpacing, 0.0);
    GET_CGFLOAT(kCTParagraphStyleSpecifierParagraphSpacingBefore, paragraphSpacingBefore, 0.0);
    GET_CGFLOAT(kCTParagraphStyleSpecifierLineHeightMultiple, lineHeightMultiple, 0.0);
    GET_CGFLOAT(kCTParagraphStyleSpecifierMaximumLineHeight, maximumLineHeight, 0.0);
    GET_CGFLOAT(kCTParagraphStyleSpecifierMinimumLineHeight, minimumLineHeight, 0.0);
    GET_CGFLOAT(kCTParagraphStyleSpecifierDefaultTabInterval, defaultTabInterval, 0.0);
    
    CTWritingDirection baseDirection;
    if (CTParagraphStyleGetValueForSpecifier(style, kCTParagraphStyleSpecifierBaseWritingDirection, sizeof(baseDirection), &(baseDirection))) {
        switch (baseDirection) {
            default:
            case kCTWritingDirectionNatural: _scalar.baseWritingDirection = OAWritingDirectionNatural; break;
            case kCTWritingDirectionLeftToRight: _scalar.baseWritingDirection = OAWritingDirectionLeftToRight; break;
            case kCTWritingDirectionRightToLeft: _scalar.baseWritingDirection = OAWritingDirectionRightToLeft; break;
        }
    }
    
    CTTextAlignment textAlignment;
    if (CTParagraphStyleGetValueForSpecifier(style, kCTParagraphStyleSpecifierAlignment, sizeof(textAlignment), &(textAlignment))) {
        switch (textAlignment) {
            case kCTLeftTextAlignment: _scalar.alignment = OALeftTextAlignment; break;
            case kCTRightTextAlignment: _scalar.alignment = OARightTextAlignment; break;
            case kCTCenterTextAlignment: _scalar.alignment = OACenterTextAlignment; break;
            case kCTJustifiedTextAlignment: _scalar.alignment = OAJustifiedTextAlignment; break;
            case kCTNaturalTextAlignment: _scalar.alignment = OANaturalTextAlignment; break;
        }
    }
    
    /* TODO: Tab stops ( kCTParagraphStyleSpecifierTabStops ) */
    /* TODO: Line break mode ( kCTParagraphStyleSpecifierLineBreakMode ) */

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

- (CFTypeRef)copyCTParagraphStyle;
{
#define OAParagraphStyleNumSettings 13
    CTParagraphStyleSetting settings[OAParagraphStyleNumSettings];
    
    // Note that these default values are the defaults used by CTParagraphStyle, not the ones used by our own style system
#define SETTING(spec_, valueType, valueValue, dflt) valueType style_ ## spec_ ## _value = (valueValue); if (( style_ ## spec_ ## _value ) != (dflt)) { settings[settingIndex].spec = spec_; settings[settingIndex].valueSize = sizeof(valueValue); settings[settingIndex].value = &( style_ ## spec_ ## _value ); settingIndex++; }
    int settingIndex = 0;
    
    SETTING(kCTParagraphStyleSpecifierFirstLineHeadIndent, CGFloat, _scalar.firstLineHeadIndent, 0.0);
    SETTING(kCTParagraphStyleSpecifierHeadIndent, CGFloat, _scalar.headIndent, 0.0);
    SETTING(kCTParagraphStyleSpecifierTailIndent, CGFloat, _scalar.tailIndent, 0.0);
    SETTING(kCTParagraphStyleSpecifierLineSpacing, CGFloat, _scalar.lineSpacing, 0.0);
    SETTING(kCTParagraphStyleSpecifierParagraphSpacing, CGFloat, _scalar.paragraphSpacing, 0.0);
    SETTING(kCTParagraphStyleSpecifierParagraphSpacingBefore, CGFloat, _scalar.paragraphSpacingBefore, 0.0);
    SETTING(kCTParagraphStyleSpecifierLineHeightMultiple, CGFloat, _scalar.lineHeightMultiple, 0.0);
    SETTING(kCTParagraphStyleSpecifierMaximumLineHeight, CGFloat, _scalar.maximumLineHeight, 0.0);
    SETTING(kCTParagraphStyleSpecifierMinimumLineHeight, CGFloat, _scalar.minimumLineHeight, 0.0);
    SETTING(kCTParagraphStyleSpecifierDefaultTabInterval, CGFloat, _scalar.defaultTabInterval, 0.0);

    /* TODO: Tab stops ( kCTParagraphStyleSpecifierTabStops ) */
    
    CTTextAlignment align;
    switch( _scalar.alignment ) {
        case OALeftTextAlignment:      align = kCTLeftTextAlignment; break;
        case OARightTextAlignment:     align = kCTRightTextAlignment; break;
        case OACenterTextAlignment:    align = kCTCenterTextAlignment; break;
        case OAJustifiedTextAlignment: align = kCTJustifiedTextAlignment; break;
        default:
        case OANaturalTextAlignment:   align = kCTNaturalTextAlignment; break;
    };
    SETTING(kCTParagraphStyleSpecifierAlignment, CTTextAlignment, align, kCTNaturalTextAlignment);
    
    /* TODO: Line break mode ( kCTParagraphStyleSpecifierLineBreakMode ) */
    
    CTWritingDirection baseDirection;
    switch (_scalar.baseWritingDirection) {
        default:
        case OAWritingDirectionNatural:     baseDirection = kCTWritingDirectionNatural; break;
        case OAWritingDirectionLeftToRight: baseDirection = kCTWritingDirectionLeftToRight; break;
        case OAWritingDirectionRightToLeft: baseDirection = kCTWritingDirectionRightToLeft; break;
    }
    SETTING(kCTParagraphStyleSpecifierBaseWritingDirection, CTWritingDirection, baseDirection, kCTWritingDirectionNatural);

    OBASSERT(settingIndex <= OAParagraphStyleNumSettings);
    
    return CTParagraphStyleCreate(settings, settingIndex);
}

#pragma mark -
#pragma mark NSCopying

- (id)copyWithZone:(NSZone *)zone;
{
    return [self retain];
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
    return [[[super defaultParagraphStyle] mutableCopy] autorelease];
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

    [_tabStops release];
    _tabStops = [tabStops copy];
}

@end

#endif
