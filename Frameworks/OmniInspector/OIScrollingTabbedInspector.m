// Copyright 2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniInspector/OIScrollingTabbedInspector.h>

#import <OmniInspector/OIAppearance.h>
#import <OmniInspector/OITabMatrix.h>
#import <OmniInspector/OIInspectorTabController.h>

RCS_ID("$Id$")

@interface OITabbedInspector (PrivateParts)
- (void)_layoutSelectedTabs;
@end

@interface OIScrollingTabbedInspector ()

@property (strong, nonatomic) IBOutlet NSScrollView *inspectorScrollView;
@property (strong, nonatomic) IBOutlet NSTextField *tabLabel;
@property (strong, nonatomic) NSLayoutConstraint *topConstraint, *bottomConstraint, *widthConstraint, *scrollViewWidthConstraint;
@property (strong, nonatomic) NSLayoutConstraint *labelCenterConstraint;
@end


@implementation OIScrollingTabbedInspector

- (NSString *)nibName;
{
    return @"OIScrollingTabbedInspector";
}

- (void)awakeFromNib;
{
    [super awakeFromNib];
    
    [self.buttonMatrix setTabMatrixHighlightStyle:OITabMatrixYosemiteHighlightStyle];
    self.tabLabel.textColor = [OIAppearance appearance].InspectorTabOnStateTintColor;
    
    NSColor *inspectorBackgroundColor = [[OIAppearance appearance] colorForKeyPath:@"InspectorBackgroundColor"];
    self.inspectorScrollView.backgroundColor = inspectorBackgroundColor;
    self.inspectorScrollView.drawsBackground = YES;

    [self.view setTranslatesAutoresizingMaskIntoConstraints:NO];
}

- (void)_layoutSelectedTabs;
{
    [super _layoutSelectedTabs];
    
    OIInspectorTabController *firstTab, *lastTab;
    for (OIInspectorTabController *tab in _tabControllers) {
        if (![tab isVisible])
            continue;
        
        if (!firstTab)
            firstTab = tab;
        
        lastTab = tab;
    }
    
    NSView *firstInspectorView = [firstTab inspectorView];
    NSView *lastInspectorView = [lastTab inspectorView];

    if (self.topConstraint.secondItem != firstInspectorView) {
        if (self.topConstraint)
            [contentView removeConstraint:self.topConstraint];
        
        self.topConstraint = [NSLayoutConstraint constraintWithItem:contentView attribute:NSLayoutAttributeTop relatedBy:NSLayoutRelationEqual toItem:firstInspectorView attribute:NSLayoutAttributeTop multiplier:1 constant:0];
        [contentView addConstraint:self.topConstraint];
    }
    
    if (self.bottomConstraint.secondItem != firstInspectorView) {
        if (self.bottomConstraint)
            [contentView removeConstraint:self.bottomConstraint];
        
        self.bottomConstraint = [NSLayoutConstraint constraintWithItem:contentView attribute:NSLayoutAttributeBottom relatedBy:NSLayoutRelationEqual toItem:lastInspectorView attribute:NSLayoutAttributeBottom multiplier:1 constant:0];
        [contentView addConstraint:self.bottomConstraint];
    }
    
    CGFloat width = firstTab.inspectorRegistry.inspectorWidth;

    if (!self.widthConstraint) {
        self.widthConstraint = [NSLayoutConstraint constraintWithItem:contentView attribute:NSLayoutAttributeWidth relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1 constant:width];
        [contentView addConstraint:self.widthConstraint];
    } else if (self.widthConstraint.constant != width) {
        self.widthConstraint.constant = width;
    }
    
    NSScroller *verticalScroller = [self.inspectorScrollView verticalScroller];
    if ([verticalScroller scrollerStyle] == NSScrollerStyleLegacy)
        width += NSWidth([verticalScroller frame]);

    if (!self.scrollViewWidthConstraint) {
        self.scrollViewWidthConstraint = [NSLayoutConstraint constraintWithItem:self.inspectorScrollView attribute:NSLayoutAttributeWidth relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1 constant:width];
        [self.inspectorScrollView addConstraint:self.scrollViewWidthConstraint];
    } else if (self.scrollViewWidthConstraint.constant != width) {
        self.scrollViewWidthConstraint.constant = width;
    }
    
    NSDictionary *views = NSDictionaryOfVariableBindings(_inspectorScrollView);
    
    [self.view addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|-0-[_inspectorScrollView]-0-|" options:0 metrics:nil views:views]];

    CGFloat tabCenter = NSMidX([self.buttonMatrix cellFrameAtRow:self.buttonMatrix.selectedRow column:self.buttonMatrix.selectedColumn]);
    
    self.tabLabel.stringValue = firstTab.inspector.displayName;
    if (!self.labelCenterConstraint) {
        self.labelCenterConstraint = [NSLayoutConstraint constraintWithItem:self.tabLabel attribute:NSLayoutAttributeCenterX relatedBy:NSLayoutRelationEqual toItem:self.buttonMatrix attribute:NSLayoutAttributeLeft multiplier:1 constant:tabCenter];
        self.labelCenterConstraint.priority = NSLayoutPriorityDefaultHigh;
        [self.view addConstraint:self.labelCenterConstraint];
    } else {
        self.labelCenterConstraint.constant = tabCenter;
    }
    
    self.view.superview.needsLayout = YES;
    [self.view.window recalculateKeyViewLoop];
}

@end
