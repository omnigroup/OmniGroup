// Copyright 2013-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OAAppearance.h>

@interface OIAppearance : OAAppearance

+ (NSColor *)dynamicColorForView:(NSView *)view darkColor:(NSColor *)darkColor lightColor:(NSColor *)lightColor;

// Inspector
@property (readonly) CGFloat InspectorSidebarWidth;
@property (readonly) CGFloat InspectorHeaderContentHeight;
@property (readonly) CGFloat InspectorHeaderSeparatorTopPadding;
@property (readonly) CGFloat InspectorHeaderSeparatorHeight;
@property (readonly) CGFloat InspectorSnoozeButtonCornerRounding;
@property (readonly) NSSize InspectorNoteTextInset;
@property (readonly) NSColor *InspectorTabOnStateTintColor;
@property (readonly) NSColor *InspectorTabHighlightedTintColor;
@property (readonly) NSColor *InspectorTabNormalTintColor;

@property (readonly) NSColor *DarkInspectorBackgroundColor;
@property (readonly) NSColor *DarkInspectorHeaderSeparatorColor;
@property (readonly) NSColor *LightInspectorBackgroundColor;
@property (readonly) NSColor *LightInspectorHeaderSeparatorColor;

- (NSColor *)inspectorBackgroundColorForView:(NSView *)view;
- (NSColor *)inspectorHeaderSeparatorColorForView:(NSView *)view;

@end
