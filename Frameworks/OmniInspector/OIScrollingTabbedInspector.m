// Copyright 2015-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniInspector/OIScrollingTabbedInspector.h>

#import <OmniInspector/OIAppearance.h>
#import <OmniInspector/OITabMatrix.h>
#import <OmniInspector/OIInspectorController.h>
#import <OmniInspector/OIInspectorTabController.h>

RCS_ID("$Id$")

@interface OITabbedInspector (PrivateParts)
- (void)_layoutSelectedTabs;
- (void)_scrollerStyleDidChange:(NSNotification *)notification;
@end

@interface OIScrollingTabbedInspector ()

@property (strong, nonatomic) IBOutlet NSScrollView *inspectorScrollView;
@property (strong, nonatomic) IBOutlet NSTextField *tabLabel;
@property (strong, nonatomic) NSLayoutConstraint *topConstraint, *bottomConstraint, *scrollViewWidthConstraint;
@property (strong, nonatomic) NSLayoutConstraint *labelCenterConstraint;
@end


@implementation OIScrollingTabbedInspector

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

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
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(_scrollerStyleDidChange:) name:NSPreferredScrollerStyleDidChangeNotification object:nil];

    [self.view setTranslatesAutoresizingMaskIntoConstraints:NO];
    [contentView setTranslatesAutoresizingMaskIntoConstraints:NO];
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
        [contentView.widthAnchor constraintGreaterThanOrEqualToAnchor:tab.inspectorView.widthAnchor constant:0].active = YES;
        [contentView.leftAnchor constraintGreaterThanOrEqualToAnchor:tab.inspectorView.leftAnchor constant:0].active = YES;
    }
    NSLayoutConstraint *compressionConstraint = [contentView.widthAnchor constraintEqualToConstant:0];
    compressionConstraint.priority = NSLayoutPriorityDefaultHigh;
    compressionConstraint.active = YES;
    
    NSView *firstInspectorView = [firstTab inspectorView];
    NSView *lastInspectorView = [lastTab inspectorView];

    if (self.topConstraint.secondItem != firstInspectorView) {
        if (self.topConstraint)
            [contentView removeConstraint:self.topConstraint];
        
        self.topConstraint = [contentView.topAnchor constraintEqualToAnchor:firstInspectorView.topAnchor];
        self.topConstraint.active = YES;
    }
    
    if (self.bottomConstraint.secondItem != lastInspectorView) {
        if (self.bottomConstraint)
            [contentView removeConstraint:self.bottomConstraint];
        
        self.bottomConstraint = [contentView.bottomAnchor constraintEqualToAnchor:lastInspectorView.bottomAnchor];
        self.bottomConstraint.active = YES;
    }
    
    if (!self.scrollViewWidthConstraint) {
        self.scrollViewWidthConstraint = [self.inspectorScrollView.widthAnchor constraintEqualToAnchor:contentView.widthAnchor];
        self.scrollViewWidthConstraint.active = YES;
    }
    [self _adjustScrollViewWidthConstraintForScrollWidth];
    
    [self.view.widthAnchor constraintEqualToAnchor:_inspectorScrollView.widthAnchor].active = YES;
     
    CGFloat tabCenter = NSMidX([self.buttonMatrix cellFrameAtRow:self.buttonMatrix.selectedRow column:self.buttonMatrix.selectedColumn]);

    NSString *displayName = firstTab.inspector.displayName;
    if (!displayName)
        displayName = @"";
    self.tabLabel.stringValue = displayName;

    if (!self.labelCenterConstraint) {
        self.labelCenterConstraint = [self.tabLabel.centerXAnchor constraintGreaterThanOrEqualToAnchor:self.buttonMatrix.leftAnchor constant:tabCenter];
        self.labelCenterConstraint.priority = NSLayoutPriorityDefaultHigh;
        self.labelCenterConstraint.active = YES;
    } else {
        self.labelCenterConstraint.constant = tabCenter;
    }
    
    self.view.superview.needsLayout = YES;
    [self.view.window recalculateKeyViewLoop];
}


- (void)_adjustScrollViewWidthConstraintForScrollWidth;
{
    CGFloat scrollerWidth = 0;
    NSScroller *verticalScroller = [self.inspectorScrollView verticalScroller];
    if ([verticalScroller scrollerStyle] == NSScrollerStyleLegacy)
        scrollerWidth = NSWidth([verticalScroller frame]);
    
    self.scrollViewWidthConstraint.constant = scrollerWidth;
}

- (void)_scrollerStyleDidChange:(NSNotification *)notification
{
    [self _adjustScrollViewWidthConstraintForScrollWidth];
}

@end
