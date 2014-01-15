// Copyright 2010-2013 The Omni Group. All rights reserved.
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

@interface OUITabBar () {
  @private
    UIFont *_tabTitleFont;
    UIFont *_selectedTabTitleFont;
}

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
}

- (NSUInteger)tabCount;
{
    return self.tabTitles.count;
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

- (void)layoutSubviews;
{
    [super layoutSubviews];
    
    if (self.tabButtons == nil) {
        NSNumberFormatter *numberFormatter = [[NSNumberFormatter alloc] init];
        [numberFormatter setNumberStyle:NSNumberFormatterDecimalStyle];
        [numberFormatter setUsesGroupingSeparator:NO];
        
        NSUInteger tabCount = self.tabCount;
        NSMutableArray *buttonsArray = [NSMutableArray array];
        
        [self.tabTitles enumerateObjectsUsingBlock:^(NSString *title, NSUInteger index, BOOL *stop) {
            UIButton *button = [OUITabBarButton tabBarButton];
            
            [button setTitle:title forState:UIControlStateNormal];
            [button addTarget:self action:@selector(selectTab:) forControlEvents:UIControlEventTouchUpInside];
            
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

- (void)drawRect:(CGRect)rect
{
    CGContextRef context = UIGraphicsGetCurrentContext();
    CGRect bounds = self.bounds;
    CGFloat widths[_tabTitles.count];
    
    memset(widths, 0, sizeof(widths));
    [self computeTabWidths:widths];
    
    CGFloat halfPixel = 0.5f / self.contentScaleFactor;
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
    
    CGContextSetLineWidth(context, 1.0f / self.contentScaleFactor);
    CGContextReplacePathWithStrokedPath(context);
    CGContextClip(context);
    CGContextDrawLinearGradient(context, [self separatorGradient], CGPointMake(CGRectGetMidX(bounds), CGRectGetMaxY(bounds)), CGPointMake(CGRectGetMidX(bounds), CGRectGetMinY(bounds)), kCGGradientDrawsBeforeStartLocation | kCGGradientDrawsAfterEndLocation);
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

- (CGGradientRef)separatorGradient;
{
    static CGGradientRef separatorGradient = NULL;
    if (separatorGradient != NULL)
        return separatorGradient;
    
    CGFloat components[] = {0.80f, 1.0f, 0.96f, 1.0f};
    CGFloat locations[] = {0.0f, 1.0f};
    CGColorSpaceRef space = CGColorSpaceCreateDeviceGray();

    separatorGradient = CGGradientCreateWithColorComponents(space, components, locations, sizeof(locations) / sizeof(CGFloat));

    CGColorSpaceRelease(space);

    return separatorGradient;
}

@end

