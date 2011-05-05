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
    
    
    OUIInspector *inspector = self.inspector;
    [inspector willBeginChangingInspectedObjects];
    {
        for (id <OUIParagraphInspection> object in self.appropriateObjectsForInspection) {
            OAParagraphStyle *style = [object paragraphStyleForInspectorSlice:self];
            
            if ([style alignment] != desiredAlignment) {
                OAMutableParagraphStyle *mutatis = [style mutableCopy];
                [mutatis setAlignment:desiredAlignment];
                [object setParagraphStyle:mutatis fromInspectorSlice:self];
                [mutatis release];
            }
        }
    }
    [inspector didEndChangingInspectedObjects];
}

- (void)updateParagraphAlignmentSegmentedControl:(OUIInspectorSegmentedControl *)segmentedControl;
{
    
    BOOL sel[OATextAlignmentMAX+1];
    for(unsigned int i = 0; i <= OATextAlignmentMAX; i++)
        sel[i] = NO;
    BOOL *selp = sel; // Can't refer to arrays in blocks, but pointers are OK...
    
#ifdef NS_BLOCKS_AVAILABLE
    __block BOOL inspectable = NO;
    [self eachAppropriateObjectForInspection:^(id object){
        id <OUIParagraphInspection> paragraph = object;
        
        OAParagraphStyle *style = [paragraph paragraphStyleForInspectorSlice:self];
        
        if (!style)
            return;
        
        inspectable = YES;
        
        OATextAlignment spanAlignment = [style alignment];
        OBASSERT_NONNEGATIVE(spanAlignment);
        if (spanAlignment <= OATextAlignmentMAX)
            selp[spanAlignment] = YES;
    }];
#else
    OBFinishPortingLater("Make the trunk 4.2 only?");
    BOOL inspectable = NO;
    for (id <OUIParagraphInspection> object in self.appropriateObjectsForInspection) {
        OAParagraphStyle *style = [object paragraphStyleForInspectorSlice:self];
        
        if (!style)
            continue;
        
        inspectable = YES;
        
        OATextAlignment spanAlignment = [style alignment];
        OBASSERT_NONNEGATIVE(spanAlignment);
        if (spanAlignment <= OATextAlignmentMAX)
            selp[spanAlignment] = YES;
    }
#endif
    
    segmentedControl.enabled = inspectable;
    
    NSUInteger segmentIndex = [segmentedControl segmentCount];
    while (segmentIndex--) {
        OUIInspectorSegmentedControlButton *segment = [segmentedControl segmentAtIndex:segmentIndex];
        NSInteger tag = [segment tag];
        
        if (tag >= 0 && tag <= OATextAlignmentMAX) {
            segment.selected = sel[tag];
        }
    }
}

#pragma mark -
#pragma mark OUIInspectorSlice subclass

- (BOOL)isAppropriateForInspectedObject:(id)object;
{
    return [object shouldBeInspectedByInspectorSlice:self protocol:@protocol(OUIParagraphInspection)];
}

- (void)updateInterfaceFromInspectedObjects:(OUIInspectorUpdateReason)reason;
{
    [super updateInterfaceFromInspectedObjects:reason];
    [self updateParagraphAlignmentSegmentedControl:alignmentControl];
}

#pragma mark -
#pragma mark UIViewController subclass

/* We would only have one view in our .nib and we'd have to do most of the setup by hand anyway, so not bothering with a .nib. */
- (void)loadView;
{
    OBPRECONDITION(alignmentControl == nil);
    
    // We'll be resized by the stack view
    OUIInspectorSegmentedControl *alignBar = [[OUIInspectorSegmentedControl alloc] initWithFrame:(CGRect){{0,0}, {OUIInspectorContentWidth,38}}];
    alignBar.sizesSegmentsToFit = YES;
    alignBar.allowsEmptySelection = YES;
    
    OUIInspectorSegmentedControlButton *button;
        
    button = [alignBar addSegmentWithImageNamed:@"OUIParagraphAlignmentLeft.png"];
    [button setTag:OALeftTextAlignment];
    
    button = [alignBar addSegmentWithImageNamed:@"OUIParagraphAlignmentCenter.png"];
    [button setTag:OACenterTextAlignment];

    button = [alignBar addSegmentWithImageNamed:@"OUIParagraphAlignmentRight.png"];
    [button setTag:OARightTextAlignment];

    button = [alignBar addSegmentWithImageNamed:@"OUIParagraphAlignmentJustified.png"];
    [button setTag:OAJustifiedTextAlignment];

    [alignBar addTarget:self action:@selector(changeParagraphAlignment:) forControlEvents:UIControlEventValueChanged];
    
    self.view = alignBar;
    alignmentControl = alignBar; // Retain moves from our local var to the ivar
}

- (void)viewDidUnload
{
    [alignmentControl release];
    alignmentControl = nil;
    
    [super viewDidUnload];
}

@end

