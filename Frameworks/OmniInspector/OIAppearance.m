// Copyright 2014-2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniInspector/OIAppearance.h>

RCS_ID("$Id$");

@interface OIAppearanceDynamicColor : NSObject
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
    return [OIAppearanceDynamicColor dynamicColorForView:view darkColor:self.DarkInspectorBackgroundColor lightColor:self.LightInspectorBackgroundColor];
}

- (NSColor *)inspectorHeaderSeparatorColorForView:(NSView *)view;
{
    return [OIAppearanceDynamicColor dynamicColorForView:view darkColor:self.DarkInspectorHeaderSeparatorColor lightColor:self.LightInspectorHeaderSeparatorColor];
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
    return OFISEQUAL(appearance.name, NSAppearanceNameVibrantDark);
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

- (NSString *)colorSpaceName;
{
    return NSStringFromClass([self class]);
}

- (nullable NSColor *)colorUsingColorSpaceName:(NSString *)colorSpace;
{
    return [self._currentColor colorUsingColorSpaceName:colorSpace];
}

- (nullable NSColor *)colorUsingColorSpaceName:(nullable NSString *)colorSpace device:(nullable NSDictionary<NSString *, id> *)deviceDescription;
{
    return [self._currentColor colorUsingColorSpaceName:colorSpace device:deviceDescription];
}

- (nullable NSColor *)colorUsingColorSpace:(NSColorSpace *)space;
{
    return [self._currentColor colorUsingColorSpace:space];
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
