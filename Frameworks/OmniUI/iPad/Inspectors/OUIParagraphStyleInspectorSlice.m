// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUIParagraphStyleInspectorSlice.h"
#import "OUIInspector.h"

#import <OmniAppKit/OAParagraphStyle.h>

#import <UIKit/UIView.h>
#import <OmniUI/OUIInspectorSegmentedControl.h>
#import <OmniUI/OUIInspectorSegmentedControlButton.h>
#import <OmniBase/OmniBase.h>

RCS_ID("$Id$");

@implementation OUIParagraphStyleInspectorSlice

- (void)dealloc;
{
    [alignmentControl release];
    alignmentControl = nil;

    [super dealloc];
}

- (IBAction)changeParagraphAlignment:(OUIInspectorSegmentedControl *)sender;
{
    OUIInspectorSegmentedControlButton *segment = [sender selectedSegment];
    if (!segment) {
        // ???
        return;
    }
    
    OATextAlignment desiredAlignment = [segment tag]; // We set up the tags in -loadView to be the same as our OATextAlignment values
    
    BOOL didMutate = NO;
    
    OUIInspector *inspector = self.inspector;
    [inspector willBeginChangingInspectedObjects];
    {
        for (id <OUIParagraphInspection> object in self.appropriateObjectsForInspection) {
            OAParagraphStyle *style = [object paragraphStyleForInspectorSlice:self];
            
            if ([style alignment] != desiredAlignment) {
                OAMutableParagraphStyle *mutatis = [style mutableCopy];
                [mutatis setAlignment:desiredAlignment];
                didMutate = YES;
                [object setParagraphStyle:mutatis fromInspectorSlice:self];
                [mutatis release];
            }
        }
    }
    [inspector didEndChangingInspectedObjects];
    
    // Update the interface
    if (didMutate)
        [self updateInterfaceFromInspectedObjects];    
}


#pragma mark -
#pragma mark OUIInspectorSlice subclass

- (BOOL)isAppropriateForInspectedObject:(id)object;
{
    return [object shouldBeInspectedByInspectorSlice:self protocol:@protocol(OUIParagraphInspection)];
}

- (void)updateInterfaceFromInspectedObjects;
{
    [super updateInterfaceFromInspectedObjects];
    
    int sel[OATextAlignmentMAX+1];
    for(unsigned int i = 0; i <= OATextAlignmentMAX; i++)
        sel[i] = 0;
    BOOL inspectable = NO;
    
    for (id <OUIParagraphInspection> object in self.appropriateObjectsForInspection) {
        OAParagraphStyle *style = [object paragraphStyleForInspectorSlice:self];
        
        if (!style)
            continue;
        
        inspectable = YES;
        
        OATextAlignment spanAlignment = [style alignment];
        OBASSERT_NONNEGATIVE(spanAlignment);
        if (spanAlignment <= OATextAlignmentMAX)
            sel[spanAlignment] ++;
    }
    
    alignmentControl.enabled = inspectable;
    
    NSUInteger segmentIndex = [alignmentControl segmentCount];
    while (segmentIndex--) {
        OUIInspectorSegmentedControlButton *segment = [alignmentControl segmentAtIndex:segmentIndex];
        NSInteger tag = [segment tag];
        
        if (tag >= 0 && tag <= OATextAlignmentMAX) {
            segment.selected = ( sel[tag] ? YES : NO );
        }
    }
}

#pragma mark -
#pragma mark UIViewController subclass

/* We would only have one view in our .nib and we'd have to do most of the setup by hand anyway, so not bothering with a .nib. */
- (void)loadView;
{
    OBPRECONDITION(alignmentControl == nil);
    
    UIView *container = [[UIView alloc] initWithFrame:(CGRect){{0, 0}, {320, 57}}];
    
    OUIInspectorSegmentedControl *alignBar = [[OUIInspectorSegmentedControl alloc] initWithFrame:(CGRect){{9,0}, {302,37}}];
    OUIInspectorSegmentedControlButton *button;
    
    [container addSubview:alignBar];
    
    button = [alignBar addSegmentWithText:NSLocalizedStringFromTableInBundle(@"Left", @"OUIInspectors", OMNI_BUNDLE, @"popover inspector button label for left-aligned paragraph text")];
    [button setTag:OALeftTextAlignment];
    
    button = [alignBar addSegmentWithText:NSLocalizedStringFromTableInBundle(@"Centered", @"OUIInspectors", OMNI_BUNDLE, @"popover inspector button label for centered paragraph text")];
    [button setTag:OACenterTextAlignment];

    button = [alignBar addSegmentWithText:NSLocalizedStringFromTableInBundle(@"Right", @"OUIInspectors", OMNI_BUNDLE, @"popover inspector button label for right-aligned paragraph text")];
    [button setTag:OARightTextAlignment];

    button = [alignBar addSegmentWithText:NSLocalizedStringFromTableInBundle(@"Justified", @"OUIInspectors", OMNI_BUNDLE, @"popover inspector button label for fully justified paragraph text")];
    [button setTag:OAJustifiedTextAlignment];

    button = [alignBar addSegmentWithText:NSLocalizedStringFromTableInBundle(@"Natural", @"OUIInspectors", OMNI_BUNDLE, @"popover inspector button label for natural alignment of text")];
    [button setTag:OANaturalTextAlignment];
    
    [alignBar addTarget:self action:@selector(changeParagraphAlignment:) forControlEvents:UIControlEventValueChanged];
    
    self.view = container;
    alignmentControl = alignBar; // Retain moves from our local var to the ivar
    [container release];
}

- (void)viewDidUnload
{
    [alignmentControl release];
    alignmentControl = nil;
    
    [super viewDidUnload];
}

@end

