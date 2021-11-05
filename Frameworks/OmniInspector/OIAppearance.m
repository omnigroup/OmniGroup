// Copyright 2014-2020 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniInspector/OIAppearance.h>

#import <OmniAppKit/NSAppearance-OAExtensions.h>

RCS_ID("$Id$");

@interface OIAppearanceDynamicColor : NSColor
+ (NSColor *)dynamicColorForView:(NSView *)view darkColor:(NSColor *)darkColor lightColor:(NSColor *)lightColor;
@property (nonatomic, weak) NSView *view;
@property (nonatomic) NSColor *darkColor;
@property (nonatomic) NSColor *lightColor;
@property (nonatomic, readonly) NSColor *_currentColor;
@end

@implementation OIAppearance

+ (NSColor *)dynamicColorForView:(NSView *)view darkColor:(NSColor *)darkColor lightColor:(NSColor *)lightColor;
{
    return [OIAppearanceDynamicColor dynamicColorForView:view darkColor:darkColor lightColor:lightColor];
}

// Inspector
@dynamic InspectorSidebarWidth;
@dynamic InspectorHeaderContentHeight;
@dynamic InspectorHeaderSeparatorTopPadding;
@dynamic InspectorHeaderSeparatorHeight;
@dynamic InspectorNoteTextInset;
@dynamic InspectorTabOnStateTintColor;
@dynamic InspectorTabHighlightedTintColor;
@dynamic InspectorTabNormalTintColor;

@dynamic DarkInspectorBackgroundColor;
@dynamic DarkInspectorHeaderSeparatorColor;
@dynamic LightInspectorBackgroundColor;
@dynamic LightInspectorHeaderSeparatorColor;

- (NSColor *)inspectorBackgroundColorForView:(NSView *)view;
{
    return [OIAppearanceDynamicColor dynamicColorForView:view darkColor:[NSColor colorNamed:@"DarkInspectorBackgroundColor" bundle:OMNI_BUNDLE] lightColor:[NSColor colorNamed:@"LightInspectorBackgroundColor" bundle:OMNI_BUNDLE]];
}

- (NSColor *)inspectorHeaderSeparatorColorForView:(NSView *)view;
{
    return [OIAppearanceDynamicColor dynamicColorForView:view darkColor:[NSColor colorNamed:@"DarkInspectorHeaderSeparatorColor" bundle:OMNI_BUNDLE] lightColor:[NSColor colorNamed:@"LightInspectorHeaderSeparatorColor" bundle:OMNI_BUNDLE]];
}

@end

@implementation OIAppearanceDynamicColor
// Subclassers of NSColor need to implement the methods colorSpaceName, set, the various methods which return the components for that color space, and the NSCoding protocol. Some other methods such as colorWithAlphaComponent:, isEqual:, colorUsingColorSpaceName:device:, and CGColor may also be implemented if they make sense for the colorspace. If isEqual: is overridden, so should hash (because if [a isEqual:b] then [a hash] == [b hash]). Mutable subclassers (if any) should also implement copyWithZone: to a true copy.

+ (OIAppearanceDynamicColor *)dynamicColorForView:(NSView *)view darkColor:(NSColor *)darkColor lightColor:(NSColor *)lightColor;
{
    OIAppearanceDynamicColor *dynamicColor = [[self alloc] init];
    dynamicColor.view = view;
    dynamicColor.darkColor = darkColor;
    dynamicColor.lightColor = lightColor;
    return (id)dynamicColor;
}

static BOOL _isDarkAppearance(NSAppearance *appearance)
{
    return appearance.OA_isDarkAppearance;
}

- (NSColor *)_currentColor;
{
    return _isDarkAppearance(self.view.effectiveAppearance) ? self.darkColor : self.lightColor;
}

#pragma mark - NSColor subclass

- (id)copyWithZone:(NSZone *)zone;
{
    return self;
}

- (nullable NSColor *)highlightWithLevel:(CGFloat)val;
{
    return [self._currentColor highlightWithLevel:val];
}

- (nullable NSColor *)shadowWithLevel:(CGFloat)val;
{
    return [self._currentColor shadowWithLevel:val];
}

- (void)set;
{
    [self._currentColor set];
}

- (void)setFill;
{
    [self._currentColor setFill];
}

- (void)setStroke;
{
    [self._currentColor setStroke];
}

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-implementations"
- (NSString *)colorSpaceName;
{
    OBASSERT_NOT_REACHED("Should not be calling deprecated API");
    return NSStringFromClass([self class]);
}

- (nullable NSColor *)colorUsingColorSpaceName:(NSString *)colorSpace;
{
    OBASSERT_NOT_REACHED("Should not be calling deprecated API");
    return [self._currentColor colorUsingColorSpaceName:colorSpace];
}

- (nullable NSColor *)colorUsingColorSpaceName:(nullable NSString *)colorSpace device:(nullable NSDictionary<NSString *, id> *)deviceDescription;
{
    OBASSERT_NOT_REACHED("Should not be calling deprecated API");
    return [self._currentColor colorUsingColorSpaceName:colorSpace device:deviceDescription];
}
#pragma clang diagnostic pop

- (nullable NSColor *)colorUsingColorSpace:(NSColorSpace *)space;
{
    return [self._currentColor colorUsingColorSpace:space];
}

- (NSColorType)type NS_AVAILABLE_MAC(10_13);
{
    return NSColorTypeComponentBased;
}

- (nullable NSColor *)colorUsingType:(NSColorType)type NS_AVAILABLE_MAC(10_13);
{
    return [self._currentColor colorUsingType:type];
}

- (nullable NSColor *)blendedColorWithFraction:(CGFloat)fraction ofColor:(NSColor *)color;
{
    return [self._currentColor blendedColorWithFraction:fraction ofColor:color];
}

- (NSColor *)colorWithAlphaComponent:(CGFloat)alpha;
{
    return [self._currentColor colorWithAlphaComponent:alpha];
}

- (CGFloat)alphaComponent;
{
    return [self._currentColor alphaComponent];
}

- (CGColorRef)CGColor;
{
    return [self._currentColor CGColor];
}

@end
