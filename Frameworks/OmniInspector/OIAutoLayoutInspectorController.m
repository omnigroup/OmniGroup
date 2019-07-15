// Copyright 2014-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OIAutoLayoutInspectorController.h"

#import <OmniAppKit/NSTextField-OAExtensions.h>

#import "OIAutolayoutInspectorHeaderView.h"

RCS_ID("$Id$");

@interface OIAutoLayoutInspectorController ()

@property (nonatomic, strong) NSView *inspectorContentView;
@property (nonatomic, strong) NSLayoutConstraint *heightConstraint;

@end

@implementation OIAutoLayoutInspectorController

- (OIAutolayoutInspectorHeaderView *)headerView;
{
    if (!self.inspector.wantsHeader)
        return nil;

    if (!_headerView) {
        NSNib *nib = [[NSNib alloc] initWithNibNamed:@"OIAutolayoutInspectorHeaderView" bundle:OMNI_BUNDLE];
        if (!nib || ![nib instantiateWithOwner:self topLevelObjects:NULL]) {
            OBASSERT_NOT_REACHED(@"Unable to load OIAutolayoutInspectorHeaderView");
            return nil;
        }
        
        OBASSERT_NOTNULL(_headerView);
        _headerView.drawsSeparator = self.drawsHeaderSeparator;
        
    }
    
    return _headerView;
}

- (IBAction)disclosureTriangleClicked:(id)sender;
{
    OBPRECONDITION(sender == self.headerView.disclosureButton);
    [self toggleExpandednessWithNewTopLeftPoint:NSZeroPoint animate:YES];
}

#pragma mark - OIInspectorController subclass

- (void)populateContainerView;
{
    // Don't call super - we want complete control over the view hierarchy
    OBPRECONDITION([[self.containerView subviews] count] == 0);
    OBPRECONDITION([self.inspector conformsToProtocol:@protocol(OIConcreteInspector)]);
    
    NSView *inspectorView = [self.inspector view];
    [self.containerView addSubview:inspectorView];
    self.inspectorContentView = inspectorView;
    
    self.inspectorContentView.translatesAutoresizingMaskIntoConstraints = NO;
    
    if (self.inspector.wantsHeader) {
        [self.containerView addSubview:self.headerView];
        self.headerView.translatesAutoresizingMaskIntoConstraints = NO;

        NSDictionary *views = NSDictionaryOfVariableBindings(_headerView, inspectorView);
        [self.containerView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[_headerView]|" options:0 metrics:nil views:views]];
        [self.containerView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[inspectorView]|" options:0 metrics:nil views:views]];
        [self.containerView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[_headerView][inspectorView]" options:0 metrics:nil views:views]];
    } else {
        NSDictionary *views = NSDictionaryOfVariableBindings(inspectorView);
        [self.containerView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"H:|[inspectorView]|" options:0 metrics:nil views:views]];
        [self.containerView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[inspectorView]" options:0 metrics:nil views:views]];
    }
    
    
    [self _updateVisibilityState];
    
    self.heightConstraint = [NSLayoutConstraint constraintWithItem:self.containerView attribute:NSLayoutAttributeHeight relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:0.0f constant:0.0f];
    [self _updateHeightConstraintConstantAnimated:NO];
    [self.containerView addConstraint:self.heightConstraint];
}

- (void)setExpanded:(BOOL)newState withNewTopLeftPoint:(NSPoint)topLeftPoint;
{
    if (newState != self.isExpanded)
        [self toggleExpandednessWithNewTopLeftPoint:topLeftPoint animate:NO];
}

- (void)toggleExpandednessWithNewTopLeftPoint:(NSPoint)topLeftPoint animate:(BOOL)animate;
{
    // topLeftPoint is a legacy argument – ignore it
    self.isExpanded = !self.isExpanded;
    
    if (animate) {
        [NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
            context.duration = 0.1;
            
            if (self.isExpanded)
                [self _updateVisibilityState];
            
            [self _updateHeightConstraintConstantAnimated:YES];
        } completionHandler:^{
            if (!self.isExpanded)
                [self _updateVisibilityState];
        }];
    } else {
        [self _updateHeightConstraintConstantAnimated:NO];
        [self _updateVisibilityState];
    }
}

- (CGFloat)headingHeight;
{
    if (self.inspector.wantsHeader)
        return [self.headerView fittingSize].height;
    
    return 0;
}

- (CGFloat)desiredHeightWhenExpanded;
{
    return [self headingHeight] + [self.inspector inspectorMinimumHeight];
}

- (void)updateTitle;
{
    [self.headerView.titleLabel setStringValueAllowingNil:[self.inspector displayName]];
}

- (void)inspectorDidResize:(OIInspector *)resizedInspector;
{
    [self inspectorDidResize:resizedInspector animateUpdates:NO];
}

- (void)inspectorDidResize:(OIInspector *)resizedInspector animateUpdates:(BOOL)animate;
{
    if (resizedInspector == self.inspector) {
        [self _updateHeightConstraintConstantAnimated:animate];
    }
}

- (void)updateExpandedness:(BOOL)allowAnimation;
{
    [super updateExpandedness:allowAnimation];
    [self _updateHeightConstraintConstantAnimated:allowAnimation];
}

#pragma mark - Private

- (void)_updateVisibilityState;
{
    self.inspectorContentView.hidden = !self.isExpanded;
    self.headerView.disclosureButton.state = (self.isExpanded ? NSControlStateValueOn : NSControlStateValueOff);
    [self updateTitle];
}

- (void)_updateHeightConstraintConstantAnimated:(BOOL)animate;
{
    CGFloat height = [self headingHeight];
    if (self.isExpanded)
        height += [self.inspector inspectorMinimumHeight];
    
    id constraint = self.heightConstraint;
    if (animate)
        constraint = [constraint animator];
    
    [constraint setConstant:height];
}

@end
