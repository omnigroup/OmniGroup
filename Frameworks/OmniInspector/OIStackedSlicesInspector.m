// Copyright 2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniInspector/OIStackedSlicesInspector.h>

#import <OmniInspector/OIAutoLayoutInspectorController.h>
#import <OmniInspector/OIInspector.h>
#import <OmniInspector/OIInspectorRegistry.h>
#import <OmniInspector/OIInspectorTabController.h>

RCS_ID("$Id$")

@interface OIStackedSlicesInspector () <NSStackViewDelegate>

@property (nonatomic, strong) NSMutableArray *sliceControllers;
@property (nonatomic, strong) IBOutlet NSStackView *containerStackView;
@property (nonatomic, weak) OIInspectorRegistry *inspectorRegistry;
@property (nonatomic, strong) OFMutableBijection *inspectorViewsByIdentifier;
@property (nonatomic, strong) NSMutableDictionary *inspectorViewWidthConstraintsByIdentifier;
//@property (nonatomic, strong) OFIEqualityConstraintManager *equalLabelWidthsConstraintManager;
//
//@property (nonatomic, strong) OFITextField *noSelectionLabel;
//
//@property (nonatomic, assign, getter = isObservingInspectorExpandednessChanges) BOOL observingInspectorExpandednessChanges;

@end

@implementation OIStackedSlicesInspector

- initWithDictionary:(NSDictionary *)dict inspectorRegistry:(OIInspectorRegistry *)inspectorRegistry bundle:(NSBundle *)sourceBundle;
{
    if ((self = [super initWithDictionary:dict inspectorRegistry:inspectorRegistry bundle:sourceBundle]) == nil)
        return nil;
    
    self.inspectorRegistry = inspectorRegistry;
    _sliceControllers = [[NSMutableArray alloc] init];

    // Read our sub-inspectors from the plist
    for (NSDictionary *slicePlist in [dict objectForKey:@"slices"]) {
        OIInspector *inspector = [OIInspector newInspectorWithDictionary:slicePlist inspectorRegistry:inspectorRegistry bundle:sourceBundle];
        
        if (!inspector) {
            // Don't log an error; OIInspector should have already if it is an error (might just be an OS version check)
            return nil;
        }

        OIAutoLayoutInspectorController *controller = [[OIAutoLayoutInspectorController alloc] initWithInspector:inspector];
        controller.interfaceType = OIInspectorInterfaceTypeEmbedded;
        
        if (!controller)
            continue;
        
        [_sliceControllers addObject:controller];
    }
    
    return self;
}

- (NSBundle *)nibBundle;
{
    return OMNI_BUNDLE;
}

- (void)viewDidLoad
{
    self.view.translatesAutoresizingMaskIntoConstraints = NO;
    
    [self.view addConstraint:[NSLayoutConstraint constraintWithItem:self.view attribute:NSLayoutAttributeWidth relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeWidth multiplier:1 constant:self.inspectorRegistry.inspectorWidth]];

    [self _installInspectorViews];
}

- (void)viewWillAppear;
{
    [super viewWillAppear];
    
    [self.view.superview addConstraint:[NSLayoutConstraint constraintWithItem:self.view attribute:NSLayoutAttributeTop relatedBy:NSLayoutRelationEqual toItem:self.view attribute:NSLayoutAttributeTop multiplier:1 constant:0]];

    [self.view.superview addConstraint:[NSLayoutConstraint constraintWithItem:self.view attribute:NSLayoutAttributeBottom relatedBy:NSLayoutRelationEqual toItem:self.view attribute:NSLayoutAttributeBottom multiplier:1 constant:0]];

    [self updateInspectorVisibility];
}

- (OIInspector *)inspectorWithIdentifier:(NSString *)identifier;
{
    for (OIInspectorController *inspectorController in _sliceControllers) {
        if ([inspectorController.identifier isEqualToString:identifier])
            return inspectorController.inspector;
    }
    
    return nil;
}


#pragma mark -
#pragma mark OIConcreteInspector protocol

- (NSPredicate *)inspectedObjectsPredicate;
{
    static NSPredicate *truePredicate = nil;
    if (!truePredicate)
        truePredicate = [NSPredicate predicateWithValue:YES];
    return truePredicate;
}

- (void)inspectObjects:(NSArray *)list
{
    for (OIInspectorTabController *slice in _sliceControllers) {
        NSArray *interestingObjects = [self.inspectorRegistry copyObjectsInterestingToInspector:slice.inspector];
        [slice.inspector inspectObjects:interestingObjects];
    }
}

- (void)_installInspectorViews;
{
    OBPRECONDITION(self.containerStackView != nil);
    OBPRECONDITION([self.containerStackView isDescendantOf:self.view]);
    OBPRECONDITION(self.inspectorViewsByIdentifier == nil);
    OBPRECONDITION(self.inspectorViewWidthConstraintsByIdentifier == nil);
    //    OBPRECONDITION(self.equalLabelWidthsConstraintManager == nil);
    
    self.inspectorViewsByIdentifier = [OFMutableBijection bijection];
    //    self.equalLabelWidthsConstraintManager = [[OFIEqualityConstraintManager alloc] initWithContainer:self attribute:NSLayoutAttributeWidth];
    
    for (OIAutoLayoutInspectorController *inspectorController in _sliceControllers) {
        [inspectorController loadInterface];
        
        [inspectorController setExpanded:YES withNewTopLeftPoint:NSZeroPoint]; // top left point should be ignored for embedded inspectors
        
        NSView *inspectorContainerView = [inspectorController containerView];
        NSString *identifier = [inspectorController identifier];
        
        [inspectorContainerView setTranslatesAutoresizingMaskIntoConstraints:NO];
        [self.containerStackView addView:inspectorContainerView inGravity:NSStackViewGravityTop];
        [inspectorContainerView addConstraint:[NSLayoutConstraint constraintWithItem:inspectorContainerView attribute:NSLayoutAttributeTop relatedBy:NSLayoutRelationEqual toItem:inspectorController.headerView attribute:NSLayoutAttributeTop multiplier:1 constant:0]];
        [inspectorContainerView addConstraint:[NSLayoutConstraint constraintWithItem:inspectorContainerView attribute:NSLayoutAttributeBottom relatedBy:NSLayoutRelationEqual toItem:[[inspectorController inspector] view] attribute:NSLayoutAttributeBottom multiplier:1 constant:0]];
        [inspectorContainerView addConstraint:[NSLayoutConstraint constraintWithItem:inspectorContainerView attribute:NSLayoutAttributeBottom relatedBy:NSLayoutRelationGreaterThanOrEqual toItem:inspectorController.headerView attribute:NSLayoutAttributeBottom multiplier:1 constant:0]];
        
        [inspectorContainerView setContentHuggingPriority:NSLayoutPriorityDefaultHigh forOrientation:NSLayoutConstraintOrientationVertical];
        
        [self.inspectorViewsByIdentifier setObject:inspectorContainerView forKey:identifier];
        [self _addInspectorWidthConstraintForIdentifier:identifier];
        
        //        OIInspector *inspector = [inspectorController inspector];
        //        if ([inspector conformsToProtocol:@protocol(OFIInspectorLabeledContentLayout)])
        //            [self.equalLabelWidthsConstraintManager addViews:[(id<OFIInspectorLabeledContentLayout>)inspector labelsRequiringEqualWidthConstraints]];
    }
    
    [self.view setNeedsUpdateConstraints:YES];
}

#pragma mark - API

- (void)invalidate;
{
    OBExpectDeallocation(_containerStackView);
    _containerStackView.delegate = nil;
    
    //    _equalLabelWidthsConstraintManager = nil;
    //
    //    _noSelectionLabel = nil;
}

- (void)updateInspectorVisibility;
{
    //    OBPRECONDITION(self.inspectorViewsByIdentifier != nil);
    
    NSSet *inspectorIdentifiers = [_sliceControllers setByPerformingBlock:^id(OIInspectorController *controller) {
        return controller.identifier;
    }];
    
    BOOL foundFirstInspector = NO;
    
    for (OIAutoLayoutInspectorController *inspectorController in _sliceControllers) {
        NSString *identifier = [inspectorController identifier];
        NSView *inspectorView = self.inspectorViewsByIdentifier[identifier];
        OBASSERT(inspectorView != nil);
        if (inspectorView == nil)
            continue;
        
        NSStackViewVisibilityPriority newPriority = [inspectorIdentifiers containsObject:[inspectorController identifier]] ? NSStackViewVisibilityPriorityMustHold : NSStackViewVisibilityPriorityNotVisible;
        [self.containerStackView setVisibilityPriority:newPriority forView:inspectorView];
        
        if (newPriority == NSStackViewVisibilityPriorityMustHold && !foundFirstInspector) {
            inspectorController.drawsHeaderSeparator = NO;
            foundFirstInspector = YES;
        } else {
            inspectorController.drawsHeaderSeparator = YES;
        }
        
        [self.view setNeedsUpdateConstraints:YES];
    }
    
    //    [self.noSelectionLabel setHidden:foundFirstInspector];
}

#pragma mark - NSView subclass

- (BOOL)isFlipped;
{
    return YES;
}

- (NSRect)adjustScroll:(NSRect)newVisible;
{
    // Disallow horizontal scrolling
    newVisible.origin.x = 0;
    return newVisible;
}

//- (void)mouseDown:(NSEvent *)theEvent;
//{
//    [self.view.window makeFirstResponder:self];
//}

#pragma mark Constraints & helpers

- (void)_removeInspectorWidthConstraintForIdentifier:(NSString *)identifier;
{
    OBPRECONDITION(self.inspectorViewWidthConstraintsByIdentifier != nil);
    OBPRECONDITION(self.inspectorViewWidthConstraintsByIdentifier[identifier] != nil);
    
    [self.view removeConstraint:self.inspectorViewWidthConstraintsByIdentifier[identifier]];
//    [self.inspectorViewWidthConstraintsByIdentifier removeObjectForKey:identifier];
}

- (void)_addInspectorWidthConstraintForIdentifier:(NSString *)identifier;
{
    if (self.inspectorViewWidthConstraintsByIdentifier == nil) {
        self.inspectorViewWidthConstraintsByIdentifier = [NSMutableDictionary dictionary];
    }
    
    OBASSERT(self.inspectorViewWidthConstraintsByIdentifier[identifier] == nil);
    
    NSView *view = self.inspectorViewsByIdentifier[identifier];
    
    NSLayoutConstraint *constraint = [NSLayoutConstraint constraintWithItem:view
                                                                  attribute:NSLayoutAttributeWidth
                                                                  relatedBy:NSLayoutRelationEqual
                                                                     toItem:self.view
                                                                  attribute:NSLayoutAttributeWidth
                                                                 multiplier:1.0f
                                                                   constant:0.0f];
    
    [self.view addConstraint:constraint];
    self.inspectorViewWidthConstraintsByIdentifier[identifier] = constraint;
}

#pragma mark - NSStackViewDelegate

- (void)stackView:(NSStackView *)stackView willDetachViews:(NSArray *)views;
{
    OBPRECONDITION(stackView == self.containerStackView);
    
    for (NSView *view in views) {
        OBASSERT([[self.inspectorViewsByIdentifier allObjects] containsObject:view]);
        
        NSString *identifier = [self.inspectorViewsByIdentifier keyForObject:view];
        [self _removeInspectorWidthConstraintForIdentifier:identifier];
        //
        //        OIInspectorController *inspectorController = [self.inspectorRegistry controllerWithIdentifier:identifier];
        //        OIInspector *inspector = [inspectorController inspector];
        //        if ([inspector conformsToProtocol:@protocol(OFIInspectorLabeledContentLayout)])
        //            [self.equalLabelWidthsConstraintManager removeViews:[(id<OFIInspectorLabeledContentLayout>)inspector labelsRequiringEqualWidthConstraints]];
    }
}

- (void)stackView:(NSStackView *)stackView didReattachViews:(NSArray *)views;
{
    OBPRECONDITION(stackView == self.containerStackView);
    
    for (NSView *view in views) {
        OBASSERT([[self.inspectorViewsByIdentifier allObjects] containsObject:view]);
        NSString *identifier = [self.inspectorViewsByIdentifier keyForObject:view];
        [self _addInspectorWidthConstraintForIdentifier:identifier];
        
        //        OIInspectorController *inspectorController = [self.inspectorRegistry controllerWithIdentifier:identifier];
        //        OIInspector *inspector = [inspectorController inspector];
        //        if ([inspector conformsToProtocol:@protocol(OFIInspectorLabeledContentLayout)])
        //            [self.equalLabelWidthsConstraintManager addViews:[(id<OFIInspectorLabeledContentLayout>)inspector labelsRequiringEqualWidthConstraints]];
    }
}

#pragma mark - NSEditor

- (BOOL)commitEditing;
{
    BOOL success = YES;
    
    for (OIInspectorController *controller in _sliceControllers) {
        //        OIInspector *inspector = OB_CHECKED_CAST(OIInspector, [controller inspector]);
        NSString *identifier = [controller identifier];
        
        if (![[self.containerStackView views] containsObject:self.inspectorViewsByIdentifier[identifier]])
            continue; // Skip views that aren't in the stack view at all (as is the case during loading/teardown)
        
        if ([self.containerStackView visibilityPriorityForView:[controller containerView]] != NSStackViewVisibilityPriorityNotVisible) {
            //            success = success && [inspector commitEditing];
        }
    }
    
    return success;
}

#pragma mark - Private

- (void)_installNoSelectionLabel;
{
#if 0
    NSView *scrollView = [self enclosingScrollView];
    NSView *container = [scrollView superview];
    
    self.noSelectionLabel = [[OFITextField alloc] init];
    self.noSelectionLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.noSelectionLabel.editable = NO;
    self.noSelectionLabel.selectable = NO;
    self.noSelectionLabel.drawsBackground = NO;
    self.noSelectionLabel.bordered = NO;
    
    NSShadow *noSelectionShadow = [[NSShadow alloc] init];
    noSelectionShadow.shadowColor = [NSColor colorWithWhite:1.0f alpha:0.75f];
    noSelectionShadow.shadowOffset = (NSSize){.width = 0, .height = -1.0f};
    NSString *noSelection = NSLocalizedStringFromTableInBundle(@"No Selection", @"OmniInspector", [OIInspectorRegistry bundle], @"no selection placeholder string");
    NSDictionary *attributes = @{ NSFontAttributeName : [NSFont boldSystemFontOfSize:20.0f],
                                  NSForegroundColorAttributeName : [NSColor colorWithCalibratedHue:0.0f saturation:0.0f brightness:0.75f alpha:1.0f],
                                  NSShadowAttributeName : noSelectionShadow };
    NSAttributedString *noSelectionString = [[NSAttributedString alloc] initWithString:noSelection
                                                                            attributes:attributes];
    self.noSelectionLabel.attributedStringValue = noSelectionString;
    
    [container addSubview:self.noSelectionLabel];
    [container addConstraint:[NSLayoutConstraint constraintWithItem:self.noSelectionLabel
                                                          attribute:NSLayoutAttributeCenterX
                                                          relatedBy:NSLayoutRelationEqual
                                                             toItem:scrollView
                                                          attribute:NSLayoutAttributeCenterX
                                                         multiplier:1.0f
                                                           constant:0.0f]];
    [container addConstraint:[NSLayoutConstraint constraintWithItem:self.noSelectionLabel
                                                          attribute:NSLayoutAttributeCenterY
                                                          relatedBy:NSLayoutRelationEqual
                                                             toItem:scrollView
                                                          attribute:NSLayoutAttributeCenterY
                                                         multiplier:1.0f
                                                           constant:0.0f]];
#endif
}

#pragma mark Notifications

//- (void)windowDidChangeKeyOrFirstResponder;
//{
//    if (![self.window isKeyWindow]) {
//        [self commitEditing];
//    }
//}
//

@end
