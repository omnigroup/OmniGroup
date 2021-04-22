// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUITextExampleInspectorSlice.h>

#import <OmniUI/OUIParameters.h>
#import <OmniUI/OUIInspector.h>
#import <OmniAppKit/OATextAttributes.h>
#import <OmniAppKit/OAColor.h>
#import <OmniUI/OUITextSelectionSpan.h>
#import <OmniUI/OUITextView.h>

#import "OUIInspectorTextExampleView.h"

RCS_ID("$Id$");

NSString * const OUITextExampleInspectorSliceExampleString = @"Hwæt! We Gardena in geardagum"; // For subclasses

@implementation OUITextExampleInspectorSlice

#pragma mark - UIViewController subclass

+ (UIEdgeInsets)sliceAlignmentInsets;
{
    return (UIEdgeInsets) { .left = 0.0f, .right = 0.0f, .top = 0.0f, .bottom = 0.0f };
}

- (void)loadView;
{
    CGRect frame = CGRectMake(0, 0, [OUIInspector defaultInspectorContentWidth], kOUIInspectorWellHeight); // The height will be preserved, but the rest will be munged by the stacking.
    
    self.view = [[OUIInspectorTextExampleView alloc] initWithFrame:frame];
    NSMutableArray *constraintsToActivate = [NSMutableArray array];
    [constraintsToActivate addObject:[self.view.heightAnchor constraintEqualToConstant:kOUIInspectorWellHeight]];
    [NSLayoutConstraint activateConstraints:constraintsToActivate];
}

// Subclassing point; we handle text selection ranges in OUITextView, but things that inspect objects of other types will need to subclass this and -isAppropriateForInspectedObject:.

- (NSAttributedString *)makeExampleAttributedString;
{
    OUITextSelectionSpan *firstSpan = nil;
    OUITextView *textView = nil;
    
    for (OUITextSelectionSpan *span in self.appropriateObjectsForInspection) {
        if (!firstSpan) {
            firstSpan = span;
            textView = firstSpan.textView;
            continue;
        }
        
        UITextPosition *firstPosition = firstSpan.range.start;
        UITextPosition *thisPosition = span.range.start;
        OBASSERT(textView == span.textView);
        
        if ([textView comparePosition:thisPosition toPosition:firstPosition] == NSOrderedAscending)
            firstSpan = span;
    }
    
    OBASSERT(firstSpan);
    OBASSERT(firstSpan.textView);
    
    NSDictionary *attributes = [firstSpan.textView attributesInRange:firstSpan.range];
    return [[NSAttributedString alloc] initWithString:OUITextExampleInspectorSliceExampleString attributes:attributes];
}

#pragma mark - OUIInspectorSlice subclass

- (BOOL)isAppropriateForInspectedObject:(id)object;
{
    return [object isKindOfClass:[OUITextSelectionSpan class]];
}

- (void)updateInterfaceFromInspectedObjects:(OUIInspectorUpdateReason)reason;
{
    NSAttributedString *attributedString = [self makeExampleAttributedString];

    NSUInteger stringLength = [attributedString length];
    if (stringLength == 0) {
        OBASSERT_NOT_REACHED("No example text. Incorrectly subclassed -isAppropriateForInspectedObject: or -updateInterfaceFromInspectedObjects:");
        return;
    }
    
    // If supplied with a background color, assume the foreground color is thought out to match. But it we have no background color, AND we have not foregroundColor, AND we're doing inspector theming, we're going to pick a background color. We need to pick a foreground color to suit. 
    OUIInspectorTextExampleView *view = OB_CHECKED_CAST(OUIInspectorTextExampleView, self.view);
    UIColor *backgroundColorValue = [attributedString attribute:NSBackgroundColorAttributeName atIndex:0 effectiveRange:NULL];
    OAColor *backgroundColor;
    if (backgroundColorValue) {
        backgroundColor = [OAColor colorWithPlatformColor:backgroundColorValue];

        NSMutableAttributedString *noBackgroundAttributedString = [attributedString mutableCopy];
        [noBackgroundAttributedString removeAttribute:NSBackgroundColorAttributeName range:NSMakeRange(0, stringLength)];
        
        attributedString = noBackgroundAttributedString;
    } else {
        backgroundColor = [OAColor clearColor];
    }
    
    view.attributedString = attributedString;
    
    OBASSERT(backgroundColor);
    view.styleBackgroundColor = backgroundColor;
}

@end
