// Copyright 2010-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OUIParagraphStyleInspectorSlice.h"

#import <OmniUI/OUIInspector.h>

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
    OATextAlignment desiredAlignment;
    
    if (segment) {
        desiredAlignment = [segment tag]; // We set up the tags in -loadView to be the same as our OATextAlignment values
    } else {
        desiredAlignment = OANaturalTextAlignment; // No entry for this, but you can toggle off all the segments to get it.
    }
    
    
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
    
    UIView *container = [[UIView alloc] initWithFrame:(CGRect){{0, 0}, {320, 46}}];
    
    OUIInspectorSegmentedControl *alignBar = [[OUIInspectorSegmentedControl alloc] initWithFrame:(CGRect){{9,0}, {302,38}}];
    alignBar.sizesSegmentsToFit = YES;
    alignBar.allowsEmptySelection = YES;
    
    OUIInspectorSegmentedControlButton *button;
    
    [container addSubview:alignBar];
    
    button = [alignBar addSegmentWithImageNamed:@"OUIParagraphAlignmentLeft.png"];
    [button setTag:OALeftTextAlignment];
    
    button = [alignBar addSegmentWithImageNamed:@"OUIParagraphAlignmentCenter.png"];
    [button setTag:OACenterTextAlignment];

    button = [alignBar addSegmentWithImageNamed:@"OUIParagraphAlignmentRight.png"];
    [button setTag:OARightTextAlignment];

    button = [alignBar addSegmentWithImageNamed:@"OUIParagraphAlignmentJustified.png"];
    [button setTag:OAJustifiedTextAlignment];

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

