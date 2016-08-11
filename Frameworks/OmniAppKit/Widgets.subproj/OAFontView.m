// Copyright 1997-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/OAFontView.h>

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

#import <OmniAppKit/NSString-OAExtensions.h>
//#import <OmniAppKit/ps.h>

RCS_ID("$Id$")

@implementation OAFontView
{
    NSSize _textSize;
}

// Init and dealloc

- initWithFrame:(NSRect)frameRect
{
    if (!(self = [super initWithFrame:frameRect]))
        return nil;

    self.font = [NSFont userFontOfSize:0];

    return self;
}

//

@synthesize delegate = _weak_delegate;

- (void)setFont:(NSFont *)newFont;
{
    if (_font == newFont)
	return;

    _font = newFont;

    if (_font) {
        _fontDescription = [[NSString alloc] initWithFormat:@"%@ %.1f", _font.displayName, _font.pointSize];
    
        NSDictionary *attributes = [NSDictionary dictionaryWithObject:_font forKey:NSFontAttributeName];
        _textSize = [_fontDescription sizeWithAttributes:attributes];
        _textSize.height = (CGFloat)ceil(_textSize.height);
        _textSize.width = (CGFloat)ceil(_textSize.width);
    } else
        _textSize.height = _textSize.width = 0.0f;
    
        
    [self setNeedsDisplay:YES];
}

- (IBAction)setFontUsingFontPanel:(id)sender;
{
    if ([[self window] makeFirstResponder:self]) {
        NSFontManager *manager;
        NSFontPanel *panel;
        
        manager = [NSFontManager sharedFontManager];
        panel = [manager fontPanel: YES];
        [panel setDelegate:(id)self];
	[manager orderFrontFontPanel:sender];
    }
}

// NSFontManager sends -changeFont: up the responder chain

- (void)changeFont:(id)sender;
{
    NSFont *font = [sender convertFont:[sender selectedFont]];

    id delegate = _weak_delegate;
    if ([delegate respondsToSelector: @selector(fontView:shouldChangeToFont:)])
        if (![delegate fontView:self shouldChangeToFont:font])
            return;

    self.font = font;

    if ([delegate respondsToSelector: @selector(fontView:didChangeToFont:)])
        [delegate fontView:self didChangeToFont:font];
}

// NSFontPanel delegate


// NSView subclass

- (void)drawRect:(NSRect)rect
{
    NSRect bounds;

    bounds = [self bounds];
    if ([NSGraphicsContext currentContextDrawingToScreen])
        [[NSColor windowBackgroundColor] set];
    else
        [[NSColor whiteColor] set];
    NSRectFill(bounds);

    NSWindow *window = [self window];
    if ([window firstResponder] == self && 
	([window isKeyWindow] || [window isMainWindow])) {
	[[NSGraphicsContext currentContext] saveGraphicsState];
	NSSetFocusRingStyle(NSFocusRingOnly);
	NSRectFill(bounds);
	[[NSGraphicsContext currentContext] restoreGraphicsState];
    } 

    [[NSColor gridColor] set];
    NSFrameRect(bounds);
    [_fontDescription drawWithFont:_font color:[NSColor textColor] alignment:NSCenterTextAlignment verticallyCenter:YES inRectangle:bounds];

}

- (BOOL)isFlipped;
{
    return YES;
}

- (BOOL)isOpaque;
{
    return YES;
}

// NSResponder subclass

- (BOOL)acceptsFirstResponder;
{
    return YES;
}

- (BOOL)becomeFirstResponder;
{
    if (![super becomeFirstResponder]) 
	return NO;
    
    [[NSFontManager sharedFontManager] setSelectedFont:_font isMultiple:NO];
    [self setKeyboardFocusRingNeedsDisplayInRect:[self bounds]];
    return YES;
}

- (BOOL)resignFirstResponder;
{
    if (![super resignFirstResponder])
	return NO;
    [self setKeyboardFocusRingNeedsDisplayInRect:[self bounds]];
    return YES;
}

// Debugging

- (NSMutableDictionary *)debugDictionary;
{
    NSMutableDictionary *debugDictionary;

    debugDictionary = [super debugDictionary];
    if (_font)
        [debugDictionary setObject:_font forKey:@"font"];
    if (_fontDescription)
        [debugDictionary setObject:_fontDescription forKey:@"fontDescription"];
    [debugDictionary setObject:NSStringFromSize(_textSize) forKey:@"textSize"];
    return debugDictionary;
}

@end
