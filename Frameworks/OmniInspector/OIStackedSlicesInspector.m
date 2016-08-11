// Copyright 2015-2016 Omni Development, Inc. All rights reserved.
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
        NSString *identifier = [slicePlist objectForKey:@"identifier"];
        if ([self shouldHideSliceWithIdentifier:identifier]) // OP uses this to hide non-Pro slices
            continue;
        
        OIInspector <OIConcreteInspector> *inspector = [OIInspector inspectorWithDictionary:slicePlist inspectorRegistry:inspectorRegistry bundle:sourceBundle];
        
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
}

- (OIInspector *)inspectorWithIdentifier:(NSString *)identifier;
{
    for (OIInspectorController *inspectorController in _sliceControllers) {
        if ([inspectorController.inspectorIdentifier isEqualToString:identifier])
            return inspectorController.inspector;
    }
    
    return nil;
}

- (BOOL)shouldHideSliceWithIdentifier:(NSString *)identifier;
{
    return NO;
}

#pragma mark -
#pragma mark OIConcreteInspector protocol

- (NSPredicate *)inspectedObjectsPredicate;
{
    NSMutableArray *slicePredicates = [NSMutableArray array];
    for (OIInspectorTabController *slice in _sliceControllers) {
        [slicePredicates addObjectIfAbsent:[slice.inspector inspectedObjectsPredicate]];
    }
    return [NSCompoundPredicate orPredicateWithSubpredicates:slicePredicates];
}

- (void)inspectObjects:(NSArray *)list
{
    for (OIAutoLayoutInspectorController *slice in _sliceControllers) {
        OIInspector<OIConcreteInspector> *sliceInspector = slice.inspector;
        NSArray *interestingObjects = [self.inspectorRegistry copyObjectsInterestingToInspector:sliceInspector];
        BOOL showInspector = NO;
        for (id object in interestingObjects) {
            if ([sliceInspector shouldBeUsedForObject:object]) {
                showInspector = YES;
                break;
            }
        }
        if (showInspector) {
            [self.containerStackView setVisibilityPriority:NSStackViewVisibilityPriorityMustHold forView:[slice containerView]];
            [slice.inspector inspectObjects:interestingObjects];
        } else {
            [self.containerStackView setVisibilityPriority:NSStackViewVisibilityPriorityNotVisible forView:[slice containerView]];
            [slice.inspector inspectObjects:nil];
        }
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

    NSSet *inspectorIdentifiers = [_sliceControllers setByPerformingBlock:^id(OIInspectorController *controller) {
        return controller.inspectorIdentifier;
    }];
    BOOL foundFirstInspector = NO;

    for (OIAutoLayoutInspectorController *inspectorController in _sliceControllers) {
        NSStackViewVisibilityPriority newPriority = [inspectorIdentifiers containsObject:inspectorController.inspectorIdentifier] ? NSStackViewVisibilityPriorityMustHold : NSStackViewVisibilityPriorityNotVisible;

        if (newPriority == NSStackViewVisibilityPriorityMustHold && !foundFirstInspector) {
            inspectorController.drawsHeaderSeparator = NO;
            foundFirstInspector = YES;
        } else {
            inspectorController.drawsHeaderSeparator = YES;
        }

        NSView *inspectorContainerView = [inspectorController containerView];
        NSString *identifier = inspectorController.inspectorIdentifier;
        
        [inspectorController loadInterface];
        [inspectorController setExpanded:YES withNewTopLeftPoint:NSZeroPoint]; // top left point should be ignored for embedded inspectors
        
        [inspectorContainerView setTranslatesAutoresizingMaskIntoConstraints:NO];
        [self.containerStackView addView:inspectorContainerView inGravity:NSStackViewGravityTop];
        [self.containerStackView setVisibilityPriority:newPriority forView:inspectorContainerView];
        [inspectorContainerView addConstraint:[NSLayoutConstraint constraintWithItem:inspectorContainerView attribute:NSLayoutAttributeTop relatedBy:NSLayoutRelationEqual toItem:inspectorController.headerView attribute:NSLayoutAttributeTop multiplier:1 constant:0]];
        [inspectorContainerView addConstraint:[NSLayoutConstraint constraintWithItem:inspectorContainerView attribute:NSLayoutAttributeBottom relatedBy:NSLayoutRelationEqual toItem:[[inspectorController inspector] view] attribute:NSLayoutAttributeBottom multiplier:1 constant:0]];
        [inspectorContainerView addConstraint:[NSLayoutConstraint constraintWithItem:inspectorContainerView attribute:NSLayoutAttributeBottom relatedBy:NSLayoutRelationGreaterThanOrEqual toItem:inspectorController.headerView attribute:NSLayoutAttributeBottom multiplier:1 constant:0]];
        
        [inspectorContainerView setContentHuggingPriority:NSLayoutPriorityDefaultHigh forOrientation:NSLayoutConstraintOrientationVertical];
        
        [self.inspectorViewsByIdentifier setObject:inspectorContainerView forKey:identifier];
        [self _addInspectorWidthConstraintForIdentifier:identifier];
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
        NSString *identifier = controller.inspectorIdentifier;
        
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
