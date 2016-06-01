// Copyright 2012-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OAGradientBoxSeparator.h>

RCS_ID("$Id$");

@implementation OAGradientBoxSeparator

#pragma mark - OABoxSeparator subclass

- (void)drawLineInRect:(NSRect)rect;
{
    [self drawGradient:self.lineGradient clippingToRect:self.separatorRect];
}

- (void)drawBackgroundInRect:(NSRect)rect;
{
    [self drawGradient:self.backgroundGradient clippingToRect:self.embossRect];
}

#pragma mark - Public API

- (NSGradient *)lineGradient;
{
    if (_lineGradient != nil)
        return _lineGradient;
    
    return [self defaultGradientWithColor:self.lineColor];
}

- (NSGradient *)backgroundGradient;
{
    if (_backgroundGradient != nil)
        return _backgroundGradient;
    
    return [self defaultGradientWithColor:self.backgroundColor];
}

#pragma mark - Private methods

- (NSGradient *)defaultGradientWithColor:(NSColor *)color;
{
    NSColor *solidColor = [color copy];
    NSColor *transparentColor = [color colorWithAlphaComponent:0.0f];
    
    return [[NSGradient alloc] initWithColors:@[transparentColor, solidColor, transparentColor]];
}

- (void)drawGradient:(NSGradient *)gradient clippingToRect:(NSRect)rect;
{
    [[NSGraphicsContext currentContext] saveGraphicsState];
    NSRectClip(rect);
    
    CGPoint start = rect.origin;
    CGPoint end = NSMakePoint(rect.origin.x + rect.size.width, rect.origin.y + rect.size.height - 1);
    [gradient drawFromPoint:start toPoint:end options:0];
    
    [[NSGraphicsContext currentContext] restoreGraphicsState];
}

@end
