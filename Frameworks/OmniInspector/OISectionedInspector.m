// Copyright 2007-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniInspector/OISectionedInspector.h>

#import <AppKit/AppKit.h>
#import <OmniAppKit/OmniAppKit.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>
#import <OmniInspector/OIButtonMatrixBackgroundView.h>
#import <OmniInspector/OIInspectorController.h>
#import <OmniInspector/OIInspectorRegistry.h>
#import <OmniInspector/OIInspectorSection.h>
#import <OmniInspector/OIInspectorTabController.h>
#import <OmniInspector/OITabMatrix.h>
#import <OmniInspector/OITabbedInspector.h>
#import <OmniInspector/OITabCell.h>

RCS_ID("$Id$")

@interface OISectionedInspector (/*Private*/)
@property (strong, nonatomic) IBOutlet NSView *inspectionView;
@end

#pragma mark -

@implementation OISectionedInspector

- (void)dealloc;
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark -
#pragma mark OIInspector subclass

- initWithDictionary:(NSDictionary *)dict inspectorRegistry:(OIInspectorRegistry *)inspectorRegistry bundle:(NSBundle *)sourceBundle;
{
    if (!(self = [super initWithDictionary:dict inspectorRegistry:inspectorRegistry bundle:sourceBundle]))
	return nil;
    
    NSMutableArray <OIInspectorSection <OIConcreteInspector> *> *sectionInspectors = [[NSMutableArray alloc] init];
    
    // Read our sub-inspectors from the plist
    for (NSDictionary *sectionPlist in [dict objectForKey:@"sections"]) {
        NSDictionary *inspectorPlist = [sectionPlist objectForKey:@"inspector"];
        
        if (!inspectorPlist && [sectionPlist objectForKey:@"class"]) {
            inspectorPlist = sectionPlist;
        } else {
            if (!inspectorPlist) {
                OBASSERT_NOT_REACHED("No inspector specified for section");
                return nil;
            }
        }
        
        OIInspector <OIConcreteInspector> *inspector = [OIInspector inspectorWithDictionary:inspectorPlist inspectorRegistry:inspectorRegistry bundle:sourceBundle];
        if (!inspector)
            // Don't log an error; OIInspector should have already if it is an error (might just be an OS version check)
            continue;

        if (![inspector isKindOfClass:[OIInspectorSection class]]) {
            NSLog(@"%@ is not a subclass of OIInspectorSection.", inspector);
            continue;
        }
        OIInspectorSection <OIConcreteInspector> *section = (typeof(section))inspector;

        [sectionInspectors addObject:section];
    }
    
    _sectionInspectors = [[NSArray alloc] initWithArray:sectionInspectors];
    
    return self;
}

- (void)loadView;
{
    [super loadView];
    
    OBPRECONDITION([_sectionInspectors count] > 0);
    OBPRECONDITION([inspectionView isFlipped]); // We use an OITabbedInspectorContentView in the nib to make layout easier.
    
    NSBox *priorDivider = nil;
    for (OIInspectorSection *section in _sectionInspectors) {
        NSView *view = [section view];
        [inspectionView addSubview:view];

        if (!priorDivider)
            [[inspectionView topAnchor] constraintEqualToAnchor:[view topAnchor]].active = YES;
        else
            [[priorDivider bottomAnchor] constraintEqualToAnchor:[view topAnchor]].active = YES;
        [[inspectionView centerXAnchor] constraintEqualToAnchor:[view centerXAnchor]].active = YES;
        
        NSBox *divider = [[NSBox alloc] initWithFrame:NSMakeRect(0,0,10,1)];
        [divider setBorderType:NSLineBorder];
        [divider setBoxType:NSBoxSeparator];
        [divider setTranslatesAutoresizingMaskIntoConstraints:NO];
        
        [inspectionView addSubview:divider];
        [[divider heightAnchor] constraintEqualToConstant:1].active = YES;
        [[divider leftAnchor] constraintEqualToAnchor:[view leftAnchor]].active = YES;
        [[divider rightAnchor] constraintEqualToAnchor:[view rightAnchor]].active = YES;
        [[view bottomAnchor] constraintEqualToAnchor:[divider topAnchor]].active = YES;
        
        priorDivider = divider;
    }
    
    [[inspectionView bottomAnchor] constraintGreaterThanOrEqualToAnchor:[priorDivider bottomAnchor]].active = YES;
}

- (void)viewWillAppear
{
    [[inspectionView leftAnchor] constraintEqualToAnchor:[[inspectionView superview] leftAnchor]].active = YES;
    [[inspectionView rightAnchor] constraintEqualToAnchor:[[inspectionView superview] rightAnchor]].active = YES;
    [[inspectionView topAnchor] constraintEqualToAnchor:[[inspectionView superview] topAnchor]].active = YES;
    [[[inspectionView superview] bottomAnchor] constraintGreaterThanOrEqualToAnchor:[inspectionView bottomAnchor]].active = YES;
}

- (void)inspectorDidResize:(OIInspector *)resizedInspector;
{
    OBASSERT(resizedInspector != self); // Don't call us if we are the resized inspector, only on ancestors of that inspector
    NSView *resizedView = [resizedInspector view];
    OBASSERT([resizedView isDescendantOf:self.view]);
    for (OIInspectorSection *section in _sectionInspectors) {
        if ([resizedView isDescendantOf:[section view]]) {
            if (resizedInspector != section) {
                [section inspectorDidResize:resizedInspector];
            }
            break;
        }
    }
}

- (void)setInspectorController:(OIInspectorController *)aController;
{
    [super setInspectorController:aController];

    // Set the controller on all of our child inspectors as well
    for (OIInspectorSection <OIConcreteInspector> *inspector in _sectionInspectors) {
        inspector.inspectorController = aController;
    }
}

#pragma mark -
#pragma mark OIConcreteInspector protocol

- (NSString *)nibName;
{
    return @"OISectionedInspector";
}

- (NSBundle *)nibBundle;
{
    return OMNI_BUNDLE;
}

- (NSPredicate *)inspectedObjectsPredicate;
{
    // Could either OR the predicates for the sub-inspectors or require that this class be subclassed to provide the overall predicate.
    //OBRequestConcreteImplementation(self, _cmd);
    
    static NSPredicate *truePredicate = nil;
    if (!truePredicate)
        truePredicate = [NSPredicate predicateWithValue:YES];
    return truePredicate;
}

- (void)inspectObjects:(NSArray *)list 
{
    for (OIInspectorSection <OIConcreteInspector> *inspector in _sectionInspectors)
        [inspector inspectObjects:[list filteredArrayUsingPredicate:[inspector inspectedObjectsPredicate]]];
}

#pragma mark -
#pragma mark NSObject (NSMenuValidation)

- (BOOL)validateMenuItem:(NSMenuItem *)item;
{
    OIInspectorController *inspectorController = self.inspectorController;
    BOOL isVisible = [inspectorController isExpanded] && [inspectorController isVisible];
    
    if  (!isVisible) {
        [item setState:NSOffState];
    }
    return YES;
}

#pragma mark -
#pragma mark Private

@synthesize inspectionView=inspectionView;

@end
