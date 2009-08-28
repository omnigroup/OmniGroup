// Copyright 2001-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OATextWithIconCell.h"

#import <Cocoa/Cocoa.h>
#import <OmniBase/OmniBase.h>

#import "NSImage-OAExtensions.h"
#import "NSAttributedString-OAExtensions.h"

RCS_ID("$Id$");

@interface NSColor (JaguarAPI)
+ (NSColor *)alternateSelectedControlColor;
+ (NSColor *)alternateSelectedControlTextColor;
@end

static NSMutableParagraphStyle *OATextWithIconCellParagraphStyle = nil;
NSString const *OATextWithIconCellStringKey = @"string";
NSString const *OATextWithIconCellImageKey = @"image";

@implementation OATextWithIconCell

+ (void)initialize;
{
    OBINITIALIZE;
    
    OATextWithIconCellParagraphStyle = [[NSMutableParagraphStyle alloc] init];
    [OATextWithIconCellParagraphStyle setLineBreakMode:NSLineBreakByTruncatingTail];
}

// Init and dealloc

- (id)init;
{
    if ([super initTextCell:@""] == nil)
        return nil;
    
    [self setImagePosition:NSImageLeft];
    [self setEditable:YES];
    [self setDrawsHighlight:YES];
    [self setScrollable:YES];
    
    return self;
}

- (void)dealloc;
{
    [icon release];
    
    [super dealloc];
}

// NSCopying protocol

- (id)copyWithZone:(NSZone *)zone;
{
    OATextWithIconCell *copy = [super copyWithZone:zone];
    
    copy->icon = [icon retain];
    copy->_oaFlags.drawsHighlight = _oaFlags.drawsHighlight;
    
    return copy;
}

// NSCell Subclass

#define TEXT_VERTICAL_OFFSET (-1.0)
#define FLIP_VERTICAL_OFFSET (-9.0)
#define BORDER_BETWEEN_EDGE_AND_IMAGE (2.0)
#define BORDER_BETWEEN_IMAGE_AND_TEXT (3.0)
#define SIZE_OF_TEXT_FIELD_BORDER (1.0)

- (NSColor *)highlightColorWithFrame:(NSRect)cellFrame inView:(NSView *)controlView;
{
    if (!_oaFlags.drawsHighlight)
        return nil;
    else
        return [super highlightColorWithFrame:cellFrame inView:controlView];
}

- (NSColor *)textColor;
{
    if (_oaFlags.settingUpFieldEditor)
        return [NSColor blackColor];
    else if (!_oaFlags.drawsHighlight && _cFlags.highlighted)
        return [NSColor textBackgroundColor];
    else
        return [super textColor];
}

#define CELL_SIZE_FUDGE_FACTOR 10.0

- (NSSize)cellSize;
{
    NSSize cellSize = [super cellSize];
    // TODO: WJS 1/31/04 -- I REALLY don't think this next line is accurate. It appears to not be used much, anyways, but still...
    cellSize.width += [icon size].width + (BORDER_BETWEEN_EDGE_AND_IMAGE * 2.0) + (BORDER_BETWEEN_IMAGE_AND_TEXT * 2.0) + (SIZE_OF_TEXT_FIELD_BORDER * 2.0) + CELL_SIZE_FUDGE_FACTOR;
    return cellSize;
}

#define _calculateDrawingRectsAndSizes \
    NSRectEdge rectEdge;  \
    NSSize imageSize; \
    \
    if (_oaFlags.imagePosition == NSImageLeft) { \
        rectEdge = NSMinXEdge; \
        imageSize = NSMakeSize(NSHeight(aRect) - 1, NSHeight(aRect) - 1); \
    } else { \
        rectEdge =  NSMaxXEdge; \
        if (icon == nil) \
            imageSize = NSZeroSize; \
        else \
            imageSize = [icon size]; \
    } \
    \
    NSRect cellFrame = aRect, ignored; \
    if (imageSize.width > 0) \
        NSDivideRect(cellFrame, &ignored, &cellFrame, BORDER_BETWEEN_EDGE_AND_IMAGE, rectEdge); \
    \
    NSRect imageRect, textRect; \
    NSDivideRect(cellFrame, &imageRect, &textRect, imageSize.width, rectEdge); \
    \
    if (imageSize.width > 0) \
        NSDivideRect(textRect, &ignored, &textRect, BORDER_BETWEEN_IMAGE_AND_TEXT, rectEdge); \
    \
    textRect.origin.y += 1.0;


- (void)drawInteriorWithFrame:(NSRect)aRect inView:(NSView *)controlView;
{
    _calculateDrawingRectsAndSizes;
    
    NSDivideRect(textRect, &ignored, &textRect, SIZE_OF_TEXT_FIELD_BORDER, NSMinXEdge);
    textRect = NSInsetRect(textRect, 1.0, 0.0);

    if (![controlView isFlipped])
        textRect.origin.y -= (textRect.size.height + FLIP_VERTICAL_OFFSET);
        
    // Draw the text
    NSMutableAttributedString *label = [[NSMutableAttributedString alloc] initWithAttributedString:[self attributedStringValue]];
    NSRange labelRange = NSMakeRange(0, [label length]);
    if ([NSColor respondsToSelector:@selector(alternateSelectedControlColor)]) {
        NSColor *highlightColor = [self highlightColorWithFrame:cellFrame inView:controlView];
        BOOL highlighted = [self isHighlighted];

        if (highlighted && [highlightColor isEqual:[NSColor alternateSelectedControlColor]]) {
            // add the alternate text color attribute.
            [label addAttribute:NSForegroundColorAttributeName value:[NSColor alternateSelectedControlTextColor] range:labelRange];
        }
    }
    
    [label addAttribute:NSParagraphStyleAttributeName value:OATextWithIconCellParagraphStyle range:labelRange];
    [label drawInRect:textRect];
    [label release];
    
    // Draw the image
    imageRect.size = imageSize;
    imageRect.origin.y += ceil((NSHeight(aRect) - imageSize.height) / 2.0);
    if ([controlView isFlipped])
        [[self icon] drawFlippedInRect:imageRect operation:NSCompositeSourceOver];
    else
        [[self icon] drawInRect:imageRect fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1.0];
}

- (BOOL)trackMouse:(NSEvent *)theEvent inRect:(NSRect)cellFrame ofView:(NSView *)controlView untilMouseUp:(BOOL)flag;
{
    return [super trackMouse:theEvent inRect:cellFrame ofView:controlView untilMouseUp:flag];
}

- (void)editWithFrame:(NSRect)aRect inView:(NSView *)controlView editor:(NSText *)textObj delegate:(id)anObject event:(NSEvent *)theEvent;
{
    _oaFlags.settingUpFieldEditor = YES;
    [super editWithFrame:aRect inView:controlView editor:textObj delegate:anObject event:theEvent];
    _oaFlags.settingUpFieldEditor = NO;
}
- (void)selectWithFrame:(NSRect)aRect inView:(NSView *)controlView editor:(NSText *)textObj delegate:(id)anObject start:(NSInteger)selStart length:(NSInteger)selLength;
{
    _calculateDrawingRectsAndSizes;
    
/* This puts us off by a single pixel vertically in OmniWeb's workspace panel. - WJS 1/31/04
    if ([controlView isFlipped])
        textRect.origin.y += TEXT_VERTICAL_OFFSET; // Move it up a pixel so we don't draw off the bottom
    else
        textRect.origin.y -= (textRect.size.height + FLIP_VERTICAL_OFFSET);
*/
    textRect.size.height -= 3.0f;
    _oaFlags.settingUpFieldEditor = YES;
    [super selectWithFrame:textRect inView:controlView editor:textObj delegate:anObject start:selStart length:selLength];
    _oaFlags.settingUpFieldEditor = NO;
}

- (void)setObjectValue:(id <NSObject, NSCopying>)obj;
{
    if ([obj isKindOfClass:[NSString class]] || [obj isKindOfClass:[NSAttributedString class]]) {
        [super setObjectValue:obj];
        return;
    } else if ([obj isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dictionary = (NSDictionary *)obj;
        
        [super setObjectValue:[dictionary objectForKey:OATextWithIconCellStringKey]];
        [self setIcon:[dictionary objectForKey:OATextWithIconCellImageKey]];
    }
}

// API

- (NSImage *)icon;
{
    return icon;
}

- (void)setIcon:(NSImage *)anIcon;
{
    if (anIcon == icon)
        return;
    [icon release];
    icon = [anIcon retain];
}

- (NSCellImagePosition)imagePosition;
{
    return _oaFlags.imagePosition;
}
- (void)setImagePosition:(NSCellImagePosition)aPosition;
{
    _oaFlags.imagePosition = aPosition;
}


- (BOOL)drawsHighlight;
{
    return _oaFlags.drawsHighlight;
}

- (void)setDrawsHighlight:(BOOL)flag;
{
    _oaFlags.drawsHighlight = flag;
}

- (NSRect)textRectForFrame:(NSRect)aRect inView:(NSView *)controlView;
{
    _calculateDrawingRectsAndSizes;
    
    return textRect;
}


@end
