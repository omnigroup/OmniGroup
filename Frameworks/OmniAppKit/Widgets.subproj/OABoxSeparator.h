// Copyright 2010-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.


#import <AppKit/NSBox.h>

// This subclass allows you to choose a color other than black for the separator line.  The default color here is 70% gray (which tends to look a lot better than black).

@interface OABoxSeparator : NSBox

@property (nonatomic,retain) NSColor *lineColor;
@property (nonatomic,retain) NSColor *backgroundColor;

@property (nonatomic) NSBackgroundStyle backgroundStyle;

- (NSRect)separatorRect; // The rect, relative to this view's bounds, in which the line will be drawn
- (NSRect)embossRect; // The rect, relative to this view's bounds, in which the background (underhighlight/shadow) will be drawn

// Equivalents to -drawRect: for the line and background, respectively
// The -drawRect: implementation on this class calls each of these at most once
- (void)drawLineInRect:(NSRect)rect;
- (void)drawBackgroundInRect:(NSRect)rect;

@end
