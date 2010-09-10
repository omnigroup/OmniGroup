// Copyright 2007, 2010 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OISectionedInspector.h"

#import <AppKit/AppKit.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>
#import <OmniAppKit/OmniAppKit.h>

#import "OIInspectorController.h"
#import "OIInspectorRegistry.h"
#import "OIInspectorSection.h"
#import "OIInspectorTabController.h"
#import "OITabCell.h"
#import "OITabMatrix.h"
#import "OIButtonMatrixBackgroundView.h"

RCS_ID("$Id$")

@interface OISectionedInspector (/*Private*/)
- (void)_layoutSections;
@end

#pragma mark -

@implementation OISectionedInspector

- (void)dealloc;
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    [_sectionInspectors release];
    [super dealloc];
}

- (void)awakeFromNib;
{
    float inspectorWidth = [[OIInspectorRegistry sharedInspector] inspectorWidth];
    
    NSRect inspectionFrame = [inspectionView frame];
    OBASSERT(inspectionFrame.size.width <= inspectorWidth); // OK to make views from nibs wider, but probably indicates a problem if we are making them smaller.
    inspectionFrame.size.width = inspectorWidth;
    [inspectionView setFrame:inspectionFrame];
    
    
    [self _layoutSections];
}

#pragma mark -
#pragma mark OIInspector subclass

- initWithDictionary:(NSDictionary *)dict bundle:(NSBundle *)sourceBundle;
{
    if (![super initWithDictionary:dict bundle:sourceBundle])
	return nil;
    
    NSMutableArray *sectionInspectors = [[NSMutableArray alloc] init];
    
    // Read our sub-inspectors from the plist
    for (NSDictionary *sectionPlist in [dict objectForKey:@"sections"]) {
        NSDictionary *inspectorPlist = [sectionPlist objectForKey:@"inspector"];
        
        if (!inspectorPlist && [sectionPlist objectForKey:@"class"]) {
            inspectorPlist = sectionPlist;
        } else {
            if (!inspectorPlist) {
                OBASSERT_NOT_REACHED("No inspector specified for section");
                [sectionInspectors release];
                [self release];
                return nil;
            }
        }
        
        OIInspector *inspector = [OIInspector newInspectorWithDictionary:inspectorPlist bundle:sourceBundle];
        if (!inspector)
            // Don't log an error; OIInspector should have already if it is an error (might just be an OS version check)
            continue;

        if (![inspector isKindOfClass:[OIInspectorSection class]]) {
            NSLog(@"%@ is not a subclass of OIInspectorSection.", inspector);
            [inspector release];
            continue;
        }
        
	[sectionInspectors addObject:inspector];
	[inspector release];
    }
    
    _sectionInspectors = [[NSArray alloc] initWithArray:sectionInspectors];
    [sectionInspectors release];
    
    return self;
}

- (void)inspectorDidResize:(OIInspector *)resizedInspector;
{
    OBASSERT(resizedInspector != self); // Don't call us if we are the resized inspector, only on ancestors of that inspector
    NSView *resizedView = [resizedInspector inspectorView];
    OBASSERT([resizedView isDescendantOf:[self inspectorView]]);
    for (OIInspectorSection *section in _sectionInspectors) {
        if ([resizedView isDescendantOf:[section inspectorView]]) {
            if (resizedInspector != section) {
                [section inspectorDidResize:resizedInspector];
            }
            break;
        }
    }
    [self _layoutSections];
}

#pragma mark -
#pragma mark OIConcreteInspector protocol

- (NSView *)inspectorView;
{
    if (!inspectionView)
        [OMNI_BUNDLE loadNibNamed:@"OISectionedInspector" owner:self];

    OBPOSTCONDITION(inspectionView);
    return inspectionView;
}

- (NSPredicate *)inspectedObjectsPredicate;
{
    // Could either OR the predicates for the sub-inspectors or require that this class be subclassed to provide the overall predicate.
    //OBRequestConcreteImplementation(self, _cmd);
    
    static NSPredicate *truePredicate = nil;
    if (!truePredicate)
        truePredicate = [[NSPredicate predicateWithValue:YES] retain];
    return truePredicate;
}

- (void)inspectObjects:(NSArray *)list 
{
    for (OIInspector *inspector in _sectionInspectors)
        [inspector inspectObjects:[list filteredArrayUsingPredicate:[inspector inspectedObjectsPredicate]]];
}

#pragma mark -
#pragma mark NSObject (OIInspectorOptionalMethods)

- (void)setInspectorController:(OIInspectorController *)aController;
{
    _nonretained_inspectorController = aController;

    // Set the controller on all of our child inspectors as well
    for (OIInspector *inspector in _sectionInspectors) {
        if ([inspector respondsToSelector:_cmd]) {
            [inspector setInspectorController:aController];
        }
    }
}

#pragma mark -
#pragma mark NSObject (NSMenuValidation)

- (BOOL)validateMenuItem:(NSMenuItem *)item;
{
    BOOL isVisible = [_nonretained_inspectorController isExpanded] && [_nonretained_inspectorController isVisible];
    
    if  (!isVisible) {
        [item setState:NSOffState];
    } else if ([item action] == @selector(switchToInspector:)) {
	// one of our tabs
	OIInspectorTabController *tab = [item representedObject];
	[item setState:[tab isVisible] ? NSOnState : NSOffState];
    }
    return YES;
}

#pragma mark -
#pragma mark Private

- (void)_layoutSections;
{
    OBPRECONDITION([_sectionInspectors count] > 0);
    OBPRECONDITION([inspectionView isFlipped]); // We use an OITabbedInspectorContentView in the nib to make layout easier.
    
    NSSize size = NSMakeSize([inspectionView frame].size.width, 0);
    
    NSUInteger sectionIndex, sectionCount = [_sectionInspectors count];
    
    NSView *veryFirstKeyView = nil;
    NSView *previousLastKeyView = nil;

    for (sectionIndex = 0; sectionIndex < sectionCount; sectionIndex++) {
        OIInspectorSection *section = [_sectionInspectors objectAtIndex:sectionIndex];

        if (sectionIndex > 0) {
            NSRect dividerFrame = [inspectionView frame];
            dividerFrame.origin.y = size.height;
            dividerFrame.size.height = 1;
            
            NSBox *divider = [[NSBox alloc] initWithFrame:dividerFrame];
            [divider setBorderType:NSLineBorder];
            [divider setBoxType:NSBoxSeparator];
            
            [inspectionView addSubview:divider];
            [divider release];
            
            size.height += 1;
	}
	
        NSView *view = [section inspectorView];
        NSRect viewFrame = [view frame];
	OBASSERT(viewFrame.size.width <= size.width); // make sure it'll fit
	
        viewFrame.origin.x = (CGFloat)floor((size.width - viewFrame.size.width) / 2.0);
        viewFrame.origin.y = size.height;
        viewFrame.size = [view frame].size;
        [view setFrame:viewFrame];
	[inspectionView addSubview:view];
	
        size.height += [view frame].size.height;
        
        // Stitch the key view loop together
        NSView *firstKeyView = [section firstKeyView];
        if (firstKeyView) {
            if (!veryFirstKeyView)
                veryFirstKeyView = firstKeyView;
            
            // Find the last key view in this section
            NSView *lastKeyView = firstKeyView;
            while ([lastKeyView nextKeyView])
                lastKeyView = [lastKeyView nextKeyView];
            
            if (previousLastKeyView) {
                OBASSERT([previousLastKeyView nextKeyView] == nil);
                [previousLastKeyView setNextKeyView:firstKeyView];
            }
            
            previousLastKeyView = lastKeyView;
            OBASSERT(previousLastKeyView);
            OBASSERT([previousLastKeyView nextKeyView] == nil);
        }
    }
    
    // Close the loop from bottom back to top
    [previousLastKeyView setNextKeyView:veryFirstKeyView];
    
    NSRect contentFrame = [inspectionView frame];
    contentFrame.size.height = size.height;
    [inspectionView setFrame:contentFrame];
    
    [inspectionView setNeedsDisplay:YES];
    [_nonretained_inspectorController prepareWindowForDisplay];
    
    
}

@end
