// Copyright 2010-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIParagraphStyleInspectorSlice.h>

#import <OmniUI/OUIInspector.h>

#import <OmniAppKit/OAParagraphStyle.h>

#import <UIKit/UIView.h>
#import <OmniUI/OUISegmentedControl.h>
#import <OmniUI/OUISegmentedControlButton.h>
#import <OmniBase/OmniBase.h>

RCS_ID("$Id$");

@implementation OUIParagraphStyleInspectorSlice
{
    OUISegmentedControl *alignmentControl;
}

- (IBAction)changeParagraphAlignment:(OUISegmentedControl *)sender;
{
    OUISegmentedControlButton *segment = [sender selectedSegment];
    NSTextAlignment desiredAlignment;
    
    if (segment) {
        desiredAlignment = [segment tag]; // We set up the tags in -loadView to be the same as our OATextAlignment values
    } else {
        desiredAlignment = NSTextAlignmentNatural; // No entry for this, but you can toggle off all the segments to get it.
    }
    
    
    OUIInspector *inspector = self.inspector;
    [inspector willBeginChangingInspectedObjects];
    {
        for (id <OUIParagraphInspection> object in self.appropriateObjectsForInspection) {
            NSParagraphStyle *style = [object paragraphStyleForInspectorSlice:self];
            
            if ([style alignment] != desiredAlignment) {
                NSMutableParagraphStyle *mutatis = [style mutableCopy];
                [mutatis setAlignment:desiredAlignment];
                [object setParagraphStyle:mutatis fromInspectorSlice:self];
            }
        }
    }
    [inspector didEndChangingInspectedObjects];
}

- (void)updateParagraphAlignmentSegmentedControl:(OUISegmentedControl *)segmentedControl;
{
    NSMutableIndexSet *selectedAlignments = [NSMutableIndexSet indexSet];
    
    __block BOOL inspectable = NO;
    [self eachAppropriateObjectForInspection:^(id object){
        id <OUIParagraphInspection> paragraph = object;
        
        NSParagraphStyle *style = [paragraph paragraphStyleForInspectorSlice:self];
        
        if (!style)
            return;
        
        inspectable = YES;
        
        NSTextAlignment spanAlignment = style.alignment;
        OBASSERT_NONNEGATIVE(spanAlignment);
        [selectedAlignments addIndex:spanAlignment];
    }];
    
    segmentedControl.enabled = inspectable;
    
    NSUInteger segmentIndex = [segmentedControl segmentCount];
    while (segmentIndex--) {
        OUISegmentedControlButton *segment = [segmentedControl segmentAtIndex:segmentIndex];
        NSInteger tag = [segment tag];
        
        if ([selectedAlignments containsIndex:tag])
            segment.selected = YES;
    }
}

#pragma mark - OUIInspectorSlice subclass

- (BOOL)isAppropriateForInspectedObject:(id)object;
{
    return [object shouldBeInspectedByInspectorSlice:self protocol:@protocol(OUIParagraphInspection)];
}

- (void)updateInterfaceFromInspectedObjects:(OUIInspectorUpdateReason)reason;
{
    [super updateInterfaceFromInspectedObjects:reason];
    [self updateParagraphAlignmentSegmentedControl:alignmentControl];
}

#pragma mark - UIViewController subclass

/* We would only have one view in our .nib and we'd have to do most of the setup by hand anyway, so not bothering with a .nib. */
- (void)loadView;
{
    OBPRECONDITION(alignmentControl == nil);
    
    // We'll be resized by the stack view
    OUISegmentedControl *alignBar = [[OUISegmentedControl alloc] initWithFrame:(CGRect){{0,0}, {OUIInspectorContentWidth, [OUISegmentedControl buttonHeight]}}];
    alignBar.sizesSegmentsToFit = YES;
    alignBar.allowsEmptySelection = YES;
    
    OUISegmentedControlButton *button;
        
    button = [alignBar addSegmentWithImage:[UIImage imageNamed:@"OUIParagraphAlignmentLeft.png" inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil]];
    [button setTag:NSTextAlignmentLeft];
    button.accessibilityLabel = NSLocalizedStringFromTableInBundle(@"Left text align", @"OmniUI", OMNI_BUNDLE, @"Left Text Align button accessibility label.");
    
    button = [alignBar addSegmentWithImage:[UIImage imageNamed:@"OUIParagraphAlignmentCenter.png" inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil]];
    [button setTag:NSTextAlignmentCenter];
    button.accessibilityLabel = NSLocalizedStringFromTableInBundle(@"Center text align", @"OmniUI", OMNI_BUNDLE, @"Center Text Align button accessibility label.");

    button = [alignBar addSegmentWithImage:[UIImage imageNamed:@"OUIParagraphAlignmentRight.png" inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil]];
    [button setTag:NSTextAlignmentRight];
    button.accessibilityLabel = NSLocalizedStringFromTableInBundle(@"Right text align", @"OmniUI", OMNI_BUNDLE, @"Right Text Align button accessibility label.");

    button = [alignBar addSegmentWithImage:[UIImage imageNamed:@"OUIParagraphAlignmentJustified.png" inBundle:OMNI_BUNDLE compatibleWithTraitCollection:nil]];
    [button setTag:NSTextAlignmentJustified];
    button.accessibilityLabel = NSLocalizedStringFromTableInBundle(@"Justified text align", @"OmniUI", OMNI_BUNDLE, @"Justified Text Align button accessibility label.");

    [alignBar addTarget:self action:@selector(changeParagraphAlignment:) forControlEvents:UIControlEventValueChanged];
    
    self.view = alignBar;
    alignmentControl = alignBar; // Retain moves from our local var to the ivar
}

@end

