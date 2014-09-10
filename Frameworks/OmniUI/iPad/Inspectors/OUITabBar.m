// Copyright 2010-2014 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUITabBar.h>

#import <OmniUI/UIFont-OUIExtensions.h>
#import "OUITabBarButton.h"


RCS_ID("$Id$");

static UIFont *_DefaultTabTitleFont;
static UIFont *_DefaultSelectedTabTitleFont;

static UIFont *_DefaultVerticalTabTitleFont;
static UIFont *_DefaultVerticalSelectedTabTitleFont;

@interface OUITabBar () {
  @private
    BOOL _usesVerticalLayout;
    UIFont *_tabTitleFont;
    UIFont *_selectedTabTitleFont;
    NSUInteger _selectedTabIndex;
    UIView *_footerView;
}

@property (nonatomic, strong) NSMutableArray *tabImages;
@property (nonatomic, copy) NSArray *tabButtons;

@end

#pragma mark -

@implementation OUITabBar

+ (void)initialize;
{
    OBINITIALIZE;
    
    UIFont *font = nil;

    font = [UIFont systemFontOfSize:14.0];
    [self setDefaultTabTitleFont:font];
    
    font = [UIFont mediumSystemFontOfSize:14.0];
    [self setDefaultSelectedTabTitleFont:font];

    font = [UIFont mediumSystemFontOfSize:17.0];
    [self setDefaultVerticalTabTitleFont:font];
    
    font = [UIFont mediumSystemFontOfSize:17.0];
    [self setDefaultSelectedVerticalTabTitleFont:font];
}

+ (UIFont *)defaultTabTitleFont;
{
    return _DefaultTabTitleFont;
}

+ (void)setDefaultTabTitleFont:(UIFont *)font;
{
    _DefaultTabTitleFont = [font copy];
}

+ (UIFont *)defaultSelectedTabTitleFont;
{
    return _DefaultSelectedTabTitleFont;
}

+ (void)setDefaultSelectedTabTitleFont:(UIFont *)font;
{
    _DefaultSelectedTabTitleFont = [font copy];
}

+ (UIFont *)defaultVerticalTabTitleFont;
{
    return _DefaultVerticalTabTitleFont;
}

+ (void)setDefaultVerticalTabTitleFont:(UIFont *)font;
{
    _DefaultVerticalTabTitleFont = [font copy];
}

+ (UIFont *)defaultSelectedVerticalTabTitleFont;
{
    return _DefaultVerticalSelectedTabTitleFont;
}

+ (void)setDefaultSelectedVerticalTabTitleFont:(UIFont *)font;
{
    _DefaultVerticalSelectedTabTitleFont = [font copy];
}

- (id)initWithFrame:(CGRect)frame;
{
    self = [super initWithFrame:frame];
    if (self == nil) {
        return nil;
    }
    
    [self OUITabBar_commonInit];
    
    return self;
}

- (id)initWithCoder:(NSCoder *)coder;
{
    self = [super initWithCoder:coder];
    if (self == nil) {
        return nil;
    }
    
    [self OUITabBar_commonInit];
    
    return self;
}

- (void)OUITabBar_commonInit;
{
    self.opaque = NO;
    self.clearsContextBeforeDrawing = YES;
    self.contentMode = UIViewContentModeRedraw;
    
    self.tabTitleFont = [[self class] defaultTabTitleFont];
    self.selectedTabTitleFont = [[self class] defaultSelectedTabTitleFont];
    
    self.verticalTabTitleFont = [[self class] defaultVerticalTabTitleFont];
    self.selectedVerticalTabTitleFont = [[self class] defaultSelectedVerticalTabTitleFont];
}

- (BOOL)usesVerticalLayout;
{
    return _usesVerticalLayout;
}

- (void)setUsesVerticalLayout:(BOOL)usesVerticalLayout;
{
    if (_usesVerticalLayout != usesVerticalLayout) {
        _usesVerticalLayout = usesVerticalLayout;

        [self invalidateTabButtons];
        [self setNeedsLayout];
        [self setNeedsDisplay];
    }
}

- (UIFont *)tabTitleFont;
{
    return _tabTitleFont;
}

- (void)setTabTitleFont:(UIFont *)tabTitleFont;
{
    _tabTitleFont = [tabTitleFont copy];
    [self setNeedsLayout];
}

- (UIFont *)selectedTabTitleFont;
{
    return _selectedTabTitleFont;
}

- (void)setSelectedTabTitleFont:(UIFont *)selectedTabTitleFont;
{
    _selectedTabTitleFont = [selectedTabTitleFont copy];
    [self setNeedsLayout];
}

- (NSUInteger)tabCount;
{
    return self.tabTitles.count;
}

- (NSUInteger)selectedTabIndex;
{
    return _selectedTabIndex;
}

- (void)setSelectedTabIndex:(NSUInteger)selectedTabIndex;
{
    _selectedTabIndex = selectedTabIndex;

    [self setNeedsLayout];
    [self setNeedsDisplay];
}

- (void)setTabTitles:(NSArray *)tabTitles;
{
    _tabTitles = [tabTitles copy];
    [self invalidateTabButtons];
}

- (void)setImage:(UIImage *)image forTabWithTitle:(NSString *)tabTitle;
{
    if (self.tabTitles == nil) {
        return;
    }
    OBASSERT(self.tabImages != nil);
    
    NSUInteger index = [self.tabTitles indexOfObject:tabTitle];
    if (index == NSNotFound) {
        return;
    }
    
    self.tabImages[index] = image ?: [NSNull null];
    if (self.tabButtons != nil) {
        OBASSERT(index < [self.tabButtons count]);
        [self.tabButtons[index] setImage:[image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]
                                forState:UIControlStateNormal];
        [self.tabButtons[index] setImage:[image imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal]
                                forState:UIControlStateSelected];
    }
}

- (UIView *)footerView;
{
    return _footerView;
}

- (void)setFooterView:(UIView *)footerView;
{
    _footerView = footerView;
    [self setNeedsLayout];
}

- (void)layoutSubviews;
{
    [super layoutSubviews];
    
    [self.footerView removeFromSuperview];
    
    if (self.tabButtons == nil) {
        NSNumberFormatter *numberFormatter = [[NSNumberFormatter alloc] init];
        [numberFormatter setNumberStyle:NSNumberFormatterDecimalStyle];
        [numberFormatter setUsesGroupingSeparator:NO];
        
        NSUInteger tabCount = self.tabCount;
        NSMutableArray *buttonsArray = [NSMutableArray array];
        
        OBASSERT([self.tabImages count] == [self.tabTitles count]);
        [self.tabTitles enumerateObjectsUsingBlock:^(NSString *title, NSUInteger index, BOOL *stop) {
            UIButton *button = (_usesVerticalLayout ? [OUITabBarButton verticalTabBarButton] : [OUITabBarButton tabBarButton]);
            
            [button setTitle:title forState:UIControlStateNormal];
            [button addTarget:self action:@selector(selectTab:) forControlEvents:UIControlEventTouchUpInside];
            
            UIImage *image = self.tabImages[index];
            if (![image isNull]) {
                [button setImage:[image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]
                        forState:UIControlStateNormal];
                [button setImage:[image imageWithRenderingMode:UIImageRenderingModeAlwaysOriginal]
                        forState:UIControlStateSelected];
            }
            
            // UISegmentedControl subelements are read out as "1 of 3" using VoiceOver.
            // This is the closet approximation we can get with our custom control
            NSString *buttonIndexString = [numberFormatter stringFromNumber:@(index + 1)];
            NSString *buttonCountString = [numberFormatter stringFromNumber:@(tabCount)];
            NSString *format = NSLocalizedStringFromTableInBundle(@"%@ of %@", @"OmniUI", OMNI_BUNDLE, @"OUITabBar N of M accessibility value");
            NSString *accessibilityValue = [NSString stringWithFormat:format, buttonIndexString, buttonCountString];
            button.accessibilityValue = accessibilityValue;
            
            [self addSubview:button];
            [buttonsArray addObject:button];
        }];
        
        self.tabButtons = buttonsArray;
    }
    
    if (self.usesVerticalLayout) {
        const CGFloat buttonHeight = 64;
        NSUInteger tabCount = self.tabCount;
        CGRect remainingFrame = self.bounds;

        for (NSUInteger index = 0; index < tabCount; index ++) {
            UIButton *button = self.tabButtons[index];
            CGRect buttonFrame = CGRectZero;
            CGRectDivide(remainingFrame, &buttonFrame, &remainingFrame, buttonHeight, CGRectMinYEdge);
            
            button.frame = buttonFrame;
            button.selected = (index == _selectedTabIndex);
            
            UIFont *font = button.selected ? self.selectedVerticalTabTitleFont : self.verticalTabTitleFont;
            OBASSERT(font != nil);
            button.titleLabel.font = font;
        }
        
        if (_footerView != nil) {
            _footerView.translatesAutoresizingMaskIntoConstraints = NO;
            _footerView.autoresizingMask = (UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleWidth);
            _footerView.frame = remainingFrame;
            [self addSubview:_footerView];
        }
    } else {
        NSUInteger tabCount = self.tabCount;
        CGRect remainingFrame = self.bounds;
        CGFloat widths[tabCount];
        
        [self computeTabWidths:widths];
        
        for (NSUInteger index = 0; index < tabCount; index ++) {
            UIButton *button = self.tabButtons[index];
            CGRect buttonFrame = CGRectZero;
            CGRectDivide(remainingFrame, &buttonFrame, &remainingFrame, widths[index], CGRectMinXEdge);
            
            button.frame = buttonFrame;
            button.selected = (index == _selectedTabIndex);
            
            UIFont *font = button.selected ? self.selectedTabTitleFont : self.tabTitleFont;
            OBASSERT(font != nil);
            button.titleLabel.font = font;
        }
    }
}

- (void)drawRect:(CGRect)rect
{
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGRect bounds = self.bounds;

    if (self.usesVerticalLayout) {
        NSUInteger buttonCount = _tabButtons.count;
        CGFloat halfPixel = 0.5 / self.contentScaleFactor;
        
        // Right hand edge
        CGContextSaveGState(context);
        {
            [_tabButtons enumerateObjectsUsingBlock:^(OUITabBarButton *button, NSUInteger index, BOOL *stop) {
                CGRect buttonFrame = button.frame;
                CGFloat x = CGRectGetMaxX(bounds);

                if (_selectedTabIndex != index) {
                    CGContextMoveToPoint(context, x, CGRectGetMinY(buttonFrame));
                    CGContextAddLineToPoint(context, x, CGRectGetMaxY(buttonFrame));
                }
                
                if (index == buttonCount - 1) {
                    CGContextMoveToPoint(context, x, CGRectGetMaxY(buttonFrame));
                    CGContextAddLineToPoint(context, x, CGRectGetMaxY(bounds));
                }
            }];

            CGContextSetLineWidth(context, 20);
            CGContextReplacePathWithStrokedPath(context);
            CGContextClip(context);
            
            CGPoint startPoint = {
                .x = CGRectGetMaxX(bounds) - 10,
                .y = CGRectGetMinY(bounds)
            };
            
            CGPoint endPoint = {
                .x = CGRectGetMaxX(bounds),
                .y = CGRectGetMinY(bounds)
            };

            CGContextDrawLinearGradient(context, [self verticalTabEdgeGradient], startPoint, endPoint, 0);

            [[self separatorColor] set];
            CGContextMoveToPoint(context, CGRectGetMaxX(bounds) - halfPixel, CGRectGetMinY(bounds));
            CGContextAddLineToPoint(context, CGRectGetMaxX(bounds) - halfPixel, CGRectGetMaxY(bounds));
            CGContextSetLineWidth(context, 1.0 / self.contentScaleFactor);
            CGContextStrokePath(context);
        }
        CGContextRestoreGState(context);
        
        // Button separators
        CGContextSaveGState(context);
        {
            [[self separatorColor] set];
            [_tabButtons enumerateObjectsUsingBlock:^(OUITabBarButton *button, NSUInteger index, BOOL *stop) {
                CGRect buttonFrame = button.frame;
                
                CGContextMoveToPoint(context, CGRectGetMinX(bounds), CGRectGetMaxY(buttonFrame) - halfPixel);
                CGContextAddLineToPoint(context, CGRectGetMaxX(bounds), CGRectGetMaxY(buttonFrame) - halfPixel);
                
                
                CGContextSetLineWidth(context, index == buttonCount - 1 ? 4 : 1 / self.contentScaleFactor);
                CGContextStrokePath(context);
            }];
        }
        CGContextRestoreGState(context);
    } else {
        CGFloat widths[_tabTitles.count];
        
        memset(widths, 0, sizeof(widths));
        [self computeTabWidths:widths];
        
        CGContextSaveGState(context);
        {
            CGFloat halfPixel = 0.5 / self.contentScaleFactor;
            CGFloat x = CGRectGetMinX(bounds) + halfPixel;
            
            for (NSUInteger index = 0; index < _tabTitles.count; index++) {
                x += widths[index];
                CGContextMoveToPoint(context, x, CGRectGetMinY(bounds));
                CGContextAddLineToPoint(context, x, CGRectGetMaxY(bounds) - halfPixel*2);
                
                if (_selectedTabIndex > 0 && (_selectedTabIndex - 1) == index) {
                    CGContextMoveToPoint(context, CGRectGetMinX(bounds), CGRectGetMaxY(bounds) - halfPixel);
                    CGContextAddLineToPoint(context, x + halfPixel, CGRectGetMaxY(bounds) - halfPixel);
                } else if (_selectedTabIndex < (_tabTitles.count - 1) && (_selectedTabIndex == index)) {
                    CGContextMoveToPoint(context, x - halfPixel, CGRectGetMaxY(bounds) - halfPixel);
                    CGContextAddLineToPoint(context, CGRectGetMaxX(bounds), CGRectGetMaxY(bounds) - halfPixel);
                }
            }
            
            CGContextSetLineWidth(context, 1.0 / self.contentScaleFactor);
            CGContextReplacePathWithStrokedPath(context);
            CGContextClip(context);
            CGContextDrawLinearGradient(context, [self gradientForSeparatorBetweenHorizontalTabs], CGPointMake(CGRectGetMidX(bounds), CGRectGetMaxY(bounds)), CGPointMake(CGRectGetMidX(bounds), CGRectGetMinY(bounds)), kCGGradientDrawsBeforeStartLocation | kCGGradientDrawsAfterEndLocation);
        }
        CGContextRestoreGState(context);
    }
}

#pragma mark Accessibility

- (BOOL)isAccessibilityElement;
{
    // Only our children should be visible to VoiceOver
    return NO;
}

#pragma mark Actions

- (IBAction)selectTab:(id)sender;
{
    NSUInteger selectedTabIndex = [self.tabButtons indexOfObjectIdenticalTo:sender];
    self.selectedTabIndex = selectedTabIndex;
    [self sendActionsForControlEvents:UIControlEventValueChanged];
}

#pragma mark Private

- (void)invalidateTabButtons;
{
    for (UIButton *button in self.tabButtons) {
        [button removeFromSuperview];
    }
    
    self.tabImages = [[self.tabTitles arrayByPerformingBlock:^id(id anObject) {
        return [NSNull null];
    }] mutableCopy];
    
    self.tabButtons = nil;
    self.selectedTabIndex = NSNotFound;
    
    [self setNeedsLayout];
    [self setNeedsDisplay];
}

- (void)computeTabWidths:(CGFloat *)widths;
{
    NSUInteger tabCount = self.tabCount;
    if (tabCount == 0) {
        return;
    }
    
    NSUInteger integral = (NSUInteger)CGRectGetWidth(self.frame) / tabCount;
    NSUInteger remainder =(NSUInteger)CGRectGetWidth(self.frame) % tabCount;
    for (NSUInteger index = 0; index < _tabTitles.count; index++) {
        widths[index] = integral;
        if (index < remainder) {
            widths[index] += 1.0;
        }
    }
}

- (UIColor *)separatorColor;
{
    return [UIColor colorWithWhite:0.90 alpha:1.00];
}

- (CGGradientRef)gradientForSeparatorBetweenHorizontalTabs;
{
    static CGGradientRef separatorGradient = NULL;
    if (separatorGradient != NULL)
        return separatorGradient;
    
    CGFloat components[] = {0.80, 1.0, 0.96, 1.0};
    CGFloat locations[] = {0.0, 1.0};
    CGColorSpaceRef space = CGColorSpaceCreateDeviceGray();
    
    separatorGradient = CGGradientCreateWithColorComponents(space, components, locations, sizeof(locations) / sizeof(CGFloat));
    
    CGColorSpaceRelease(space);
    
    return separatorGradient;
}

- (CGGradientRef)verticalTabEdgeGradient;
{
    static CGGradientRef separatorGradient = NULL;
    if (separatorGradient != NULL)
        return separatorGradient;
    
    CGFloat components[] = {0.96, 0.0, 0.96, 1.0};
    CGFloat locations[] = {0.0, 1.0};
    CGColorSpaceRef space = CGColorSpaceCreateDeviceGray();
    
    separatorGradient = CGGradientCreateWithColorComponents(space, components, locations, sizeof(locations) / sizeof(CGFloat));
    
    CGColorSpaceRelease(space);
    
    return separatorGradient;
}

@end

