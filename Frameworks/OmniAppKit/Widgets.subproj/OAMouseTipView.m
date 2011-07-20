// Copyright 2002-2005, 2008, 2010-2011 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OAMouseTipView.h"

#import <Cocoa/Cocoa.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OFUtilities.h> // For OFForEachInArray
#import <OmniAppKit/NSColor-OAExtensions.h>

RCS_ID("$Id$");

#define TEXT_X_INSET (7.0f)
#define TEXT_Y_INSET (3.0f)

@interface NSColor (PrivateSystemColors)
+ (NSColor *)toolTipColor;		// tooltip background 
+ (NSColor *)toolTipTextColor;		// tooltip text
@end

@implementation OAMouseTipView

static NSParagraphStyle *mousetipParagrphStyle;

+ (void)initialize;
{
    OBINITIALIZE;
    
    NSMutableParagraphStyle *mutableParaStyle;
    
    mutableParaStyle = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
    [mutableParaStyle setAlignment:NSCenterTextAlignment];
    mousetipParagrphStyle = [mutableParaStyle copy];
    [mutableParaStyle release];
}

// API

- (void)setStyle:(OAMouseTipStyle)aStyle;
{
    if (style == aStyle)
        return;

    style = aStyle;
    
    [backgroundColor release];
    backgroundColor = nil;
    cornerRadius = 0.0f;
    [_textAttributes release];
    _textAttributes = nil;
    
    NSMutableDictionary *newTextAttributes = [[NSMutableDictionary alloc] init];
    
    switch(style) {
        default:
        case OAMouseTipTooltipStyle:
            
            if ([NSColor respondsToSelector:@selector(toolTipColor)])
                backgroundColor = [[[NSColor toolTipColor] colorWithAlphaComponent:0.9f] retain];
            else
                backgroundColor = [OARGBA(1.0, 0.98, 0.83, 0.9) retain]; // light yellow to match standard tooltip color
            
            cornerRadius = 0.0f;
            
            if ([NSColor respondsToSelector:@selector(toolTipTextColor)])
                [newTextAttributes setObject:[NSColor toolTipTextColor] forKey:NSForegroundColorAttributeName];
            else
                [newTextAttributes setObject:[NSColor controlTextColor] forKey:NSForegroundColorAttributeName];
            
            [newTextAttributes setObject:[NSFont toolTipsFontOfSize:[NSFont labelFontSize]] forKey:NSFontAttributeName];
            break;
            
        case OAMouseTipExposeStyle:
            backgroundColor = [[NSColor colorWithCalibratedWhite:0.2f alpha:0.85f] retain];
            cornerRadius = 5.0f;
            [newTextAttributes setObject:[NSFont boldSystemFontOfSize:[NSFont labelFontSize]] forKey:NSFontAttributeName];
            [newTextAttributes setObject:[NSColor whiteColor] forKey:NSForegroundColorAttributeName];
            [newTextAttributes setObject:mousetipParagrphStyle forKey:NSParagraphStyleAttributeName];
            break;

        case OAMouseTipDockStyle:
            backgroundColor = nil;
            cornerRadius = 0.0f;
            [newTextAttributes setObject:[NSFont boldSystemFontOfSize:[NSFont labelFontSize]*1.125f] forKey:NSFontAttributeName];
            [newTextAttributes setObject:[NSColor whiteColor] forKey:NSForegroundColorAttributeName];
            [newTextAttributes setObject:mousetipParagrphStyle forKey:NSParagraphStyleAttributeName];
            NSShadow *dockStyleTextShadow = [[NSShadow alloc] init];
            [dockStyleTextShadow setShadowOffset:(NSSize){0, -2}];
            [dockStyleTextShadow setShadowBlurRadius:5];
            [dockStyleTextShadow setShadowColor:[NSColor blackColor]];
            [newTextAttributes setObject:dockStyleTextShadow forKey:NSShadowAttributeName];
            [dockStyleTextShadow release];
            CGFloat strokeWidthPercent = 2.0f;
            [newTextAttributes setObject:[NSNumber numberWithCGFloat:-strokeWidthPercent] forKey:NSStrokeWidthAttributeName];
            [newTextAttributes setObject:[NSColor blackColor] forKey:NSStrokeColorAttributeName];
            [newTextAttributes setObject:[NSNumber numberWithDouble:log1p(strokeWidthPercent * 0.02f)] forKey:NSExpansionAttributeName];
            break;
    }
    
    _textAttributes = [newTextAttributes copy];
    [newTextAttributes release];
    
    [self setNeedsDisplay:YES];
}

- (void)setAttributedTitle:(NSAttributedString *)aTitle;
{
    if (aTitle == nil)
        aTitle = [[[NSAttributedString alloc] init] autorelease];
    
    NSTextStorage *titleStorage = [titleView textStorage];

    if (![titleStorage isEqualToAttributedString:aTitle]) {
        [titleStorage beginEditing];
        [titleStorage setAttributedString:aTitle];
        [titleStorage endEditing];
	[self setNeedsDisplay:YES];
    }
}

// NSView subclass

- initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];
    if (!self)
        return nil;
    
    titleView = [[NSTextView alloc] initWithFrame:[self bounds]];
    [titleView setSelectable:NO];
    [titleView setEditable:NO];
    [titleView setRichText:YES];
    [titleView setDrawsBackground:NO];
    [titleView setHorizontallyResizable:NO];
    [titleView setVerticallyResizable:NO];
    [titleView setTextContainerInset:(NSSize){TEXT_X_INSET, TEXT_Y_INSET}];
    NSTextContainer *textContainer = [titleView textContainer];
    [textContainer setLineFragmentPadding:0.0f];
    [textContainer setWidthTracksTextView:NO];
    [textContainer setHeightTracksTextView:NO];
    NSLayoutManager *layoutManager = [titleView layoutManager];
    [layoutManager setBackgroundLayoutEnabled:NO];
    
    // [titleView setMinSize:(NSSize){ 2 * TEXT_X_INSET, 2 * TEXT_Y_INSET }];
    
    [self addSubview:titleView];
    
    [self setAutoresizesSubviews:YES];
    
    style = OAMouseTipUnsetStyle;
    
    return self;
}

- (void)dealloc
{
    [titleView release];
    [_textAttributes release];
    [backgroundColor release];
    [super dealloc];
}

- (void)resizeSubviewsWithOldSize:(NSSize)oldBoundsSize
{
    OFForEachInArray([self subviews], NSView *, aSubview, {
        if (aSubview != titleView)
            [aSubview resizeWithOldSuperviewSize:oldBoundsSize];
    });
    
    [titleView setFrame:[self bounds]];
}

- (void)drawRect:(NSRect)rect;
{
    rect = self.bounds;
    [[NSColor clearColor] set];
    NSRectFill(rect);
    
    if (backgroundColor != nil) {
        [backgroundColor set];
        
        if (cornerRadius > 0.0) {
            CGFloat radius = cornerRadius;
            NSPoint point;
            NSBezierPath *path;
            
            if (NSWidth(rect) < 2*radius || NSHeight(rect) < 2*radius) {
                if (NSWidth(rect) < NSHeight(rect)) {
                    radius = NSWidth(rect) / 2;
                } else {
                    radius = NSHeight(rect) / 2;
                }
            }
            
            path = [NSBezierPath bezierPath];
            point.x = NSMinX(rect) + radius;
            point.y = NSMinY(rect);
            [path moveToPoint:point];
            point.x = NSMaxX(rect) - radius;
            point.y = NSMinY(rect) + radius;
            [path appendBezierPathWithArcWithCenter:point radius:-radius startAngle:90 endAngle:180 clockwise:NO];
            point.x = NSMaxX(rect) - radius;
            point.y = NSMaxY(rect) - radius;
            [path appendBezierPathWithArcWithCenter:point radius:-radius startAngle:180 endAngle:270 clockwise:NO];
            point.x = NSMinX(rect) + radius;
            point.y = NSMaxY(rect) - radius;
            [path appendBezierPathWithArcWithCenter:point radius:-radius startAngle:270 endAngle:360 clockwise:NO];
            point.x = NSMinX(rect) + radius;
            point.y = NSMinY(rect) + radius;
            [path appendBezierPathWithArcWithCenter:point radius:-radius startAngle:0 endAngle:90 clockwise:NO];
            [path closePath];
            
            [path fill];
        } else {
            NSRectFill(rect);
        }
    }
}

- (NSDictionary *)textAttributes;
{
    return _textAttributes;
}

- (void)setMaxSize:(NSSize)aSize;
{
    // Need to inset here because -sizeOfText outsets and can end up
    // returning values larger than 'aSize'
    aSize.width -= 2 * TEXT_X_INSET;
    aSize.height -= 2 * TEXT_Y_INSET;
    [[titleView textContainer] setContainerSize:aSize];
}

- (NSSize)sizeOfText
{
    NSLayoutManager *layoutMgr = [titleView layoutManager];
    NSTextContainer *textContainer = [titleView textContainer];
    
    // Annoying: -usedRectForTextContainer: doesn't trigger layout. So we call -glyphRangeForTextContainer: to make sure the layout manager has filled this text container with glyphs.
    [layoutMgr glyphRangeForTextContainer:textContainer];
    
    NSRect usedRect = [layoutMgr usedRectForTextContainer:textContainer];
    usedRect = NSInsetRect(usedRect, -TEXT_X_INSET, -TEXT_Y_INSET);
    return [self convertSize:usedRect.size fromView:titleView];
}

@end
