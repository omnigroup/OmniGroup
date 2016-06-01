// Copyright 2000-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OAShrinkingTextDisplayer.h>

#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>
#import <ApplicationServices/ApplicationServices.h>
#import <OmniBase/OmniBase.h>

RCS_ID("$Id$")


@interface OAShrinkingTextDisplayer (/*Private*/)
- (void)_resetBounds;
- (CGFloat)_widthOfString;
@end

@implementation OAShrinkingTextDisplayer

static NSFont *defaultFont;

+ (void)initialize;
{
    OBINITIALIZE;

    defaultFont = [NSFont messageFontOfSize:11.0f];
}


// API

- (void)setFont:(NSFont *)font;
{
    if (font == baseFont)
        return;
        
    baseFont = font;

    [self _resetBounds];
    
    [self setNeedsDisplay:YES];
}
- (NSFont *)font;
{
    return baseFont;
}

- (void)setStringValue:(NSString *)newString;
{
    if (newString == string)
        return;
        
    string = [newString copy];

    [self _resetBounds];
    
    [self setNeedsDisplay:YES];
}
- (NSString *)stringValue;
{
    return string;
}

// NSView

- (void)drawRect:(NSRect)rect;
{
    NSRect bounds = [self bounds];

    [string drawAtPoint:NSMakePoint((NSWidth(bounds) - [self _widthOfString]) / 2.0f, 0) withAttributes:[NSDictionary dictionaryWithObjectsAndKeys:baseFont ? baseFont : defaultFont, NSFontAttributeName, [NSColor controlTextColor], NSForegroundColorAttributeName, nil]];
}

- (BOOL)isFlipped;
{
    return NO;
}

- (void)setFrame:(NSRect)frameRect;
{
    [super setFrame:frameRect];
    [self _resetBounds];
}

#pragma mark -
#pragma mark Private

- (void)_resetBounds;
{
    NSRect frame = [self frame];
    CGFloat normalStringWidth = [self _widthOfString];

    if (normalStringWidth > NSWidth(frame))
        [self setBoundsSize:NSMakeSize(normalStringWidth, NSHeight(frame))];
    else
        [self setBoundsSize:frame.size];
}

- (CGFloat)_widthOfString;
{
    return [string sizeWithAttributes:[NSDictionary dictionaryWithObjectsAndKeys:baseFont ? baseFont : defaultFont, NSFontAttributeName, nil]].width;
}

@end
