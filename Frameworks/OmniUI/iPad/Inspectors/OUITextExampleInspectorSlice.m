// Copyright 2010-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUITextExampleInspectorSlice.h>

#import <OmniUI/OUIInspector.h>
#import <OmniUI/OUIEditableFrame.h>
#import <OmniAppKit/OATextAttributes.h>
#import <OmniQuartz/OQColor.h>

#import "OUIInspectorTextExampleView.h"
#import "OUEFTextSpan.h"

RCS_ID("$Id$");

NSString * const OUITextExampleInspectorSliceExmapleString = @"Hwæt! We Gardena in geardagum"; // For subclasses

@implementation OUITextExampleInspectorSlice

#pragma mark -
#pragma mark UIViewController subclass

- (void)loadView;
{
    CGRect frame = CGRectMake(0, 0, OUIInspectorContentWidth, 48); // The height will be preserved, but the rest will be munged by the stacking.
    
    self.view = [[[OUIInspectorTextExampleView alloc] initWithFrame:frame] autorelease];
}

// Subclassing point; we handle text selection ranges in OUIEditableFrame, but things that inspect objects of other types will need to subclass this and -isAppropriateForInspectedObject:.

- (NSAttributedString *)makeExampleAttributedString;
{
    OUEFTextSpan *firstSpan = nil;
    
    for (OUEFTextSpan *span in self.appropriateObjectsForInspection) {
        if (!firstSpan)
            firstSpan = span;
        else {
            if ([span range].location < [firstSpan range].location)
                firstSpan = span;
        }
    }
    
    OBASSERT(firstSpan);
    OBASSERT(firstSpan.frame);
    
    NSDictionary *attributes = [firstSpan.frame attributesInRange:firstSpan];
    return [[[NSAttributedString alloc] initWithString:OUITextExampleInspectorSliceExmapleString attributes:attributes] autorelease];
}

#pragma mark -
#pragma mark OUIInspectorSlice subclass

- (CGFloat)paddingToInspectorTop;
{
    // When we are the first slice, we should be all the way at the top of the view w/o any padding.
    return 0;
}

- (CGFloat)paddingToInspectorSides;
{
    return 0; // And all the way to the sides
}

- (BOOL)isAppropriateForInspectedObject:(id)object;
{
    return [object isKindOfClass:[OUEFTextRange class]];
}

- (void)updateInterfaceFromInspectedObjects:(OUIInspectorUpdateReason)reason;
{
    NSAttributedString *attributedString = [self makeExampleAttributedString];

    NSUInteger stringLength = [attributedString length];
    if (stringLength == 0) {
        OBASSERT_NOT_REACHED("No example text. Incorrectly subclassed -isAppropriateForInspectedObject: or -updateInterfaceFromInspectedObjects:");
        return;
    }
    
    CGColorRef backgroundColorValue = (CGColorRef)[attributedString attribute:OABackgroundColorAttributeName atIndex:0 effectiveRange:NULL];
    OQColor *backgroundColor;
    if (backgroundColorValue) {
        backgroundColor = [OQColor colorWithCGColor:backgroundColorValue];

        NSMutableAttributedString *noBackgroundAttributedString = [[attributedString mutableCopy] autorelease];
        [noBackgroundAttributedString removeAttribute:OABackgroundColorAttributeName range:NSMakeRange(0, stringLength)];
        
        attributedString = noBackgroundAttributedString;
    } else {
        backgroundColor = [OQColor clearColor];
    }
    
    OUIInspectorTextExampleView *view = (OUIInspectorTextExampleView *)self.view;
    view.attributedString = attributedString;
    
    OBASSERT(backgroundColor);
    view.styleBackgroundColor = backgroundColor;
}

@end
