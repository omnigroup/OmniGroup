// Copyright 1998-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/NSControl-OAExtensions.h>

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

RCS_ID("$Id$")

@implementation NSControl (OAExtensions)

+ (NSTimeInterval)doubleClickDelay;
{
    static NSUserDefaults *globalDefaults = nil;
    NSTimeInterval doubleClickDelay = .5;
    
    if (!globalDefaults) {
        globalDefaults = [[NSUserDefaults alloc] init];
        [globalDefaults addSuiteNamed:@"NeXT1"];
    }
    // Apple's current (retarded) system is MouseClick=0 -> .25s, 1 -> .5s, 2 -> .75s, 3 -> 1s
    // WJS 4/15/00 This is correct under OS X DP3.  Might change in future releases.
    if ([globalDefaults objectForKey:@"MouseClick"])
        doubleClickDelay = ([globalDefaults integerForKey:@"MouseClick"] + 1) * 0.25;
    
    return doubleClickDelay;
}

- (void)setCharacterWrappingStringValue:(NSString *)string;
{
    NSAttributedString *attributedString;

    attributedString = [[NSAttributedString alloc] initWithString:string attributes:[self attributedStringDictionaryWithCharacterWrapping]];

    if (![attributedString isEqual:[self attributedStringValue]])
        [self setAttributedStringValue:attributedString];

    [attributedString release];
}

- (NSMutableDictionary *)attributedStringDictionaryWithCharacterWrapping;
{
    NSMutableParagraphStyle *paragraphStyle;
    NSMutableDictionary *attributes;

    paragraphStyle = [[NSMutableParagraphStyle alloc] init];
    [paragraphStyle setLineBreakMode:NSLineBreakByCharWrapping];
    [paragraphStyle setAlignment:[self alignment]];
    
    attributes = [[NSMutableDictionary alloc] initWithObjectsAndKeys:paragraphStyle,
        NSParagraphStyleAttributeName, [self font], NSFontAttributeName, nil];
    [paragraphStyle release];

    return [attributes autorelease];
}


- (void)setStringValueIfDifferent:(NSString *)newString;
{
    if ([[self stringValue] isEqualToString:newString])
        return;

    [self setStringValue:newString];
}

- (CGFloat)cgFloatValue;
{
    // Rely on compile-time optimization of the call, and implicit conversion of the retrieved float type to our return type
    if (sizeof(CGFloat) > sizeof(float)) {
        return [self doubleValue];
    } else {
        return [self floatValue];
    }
}

- (void)sizeToFitVertically;
{
    [self setFrameSize:[self desiredFrameSize:NSViewHeightSizable]];
}

- (NSSize)desiredFrameSize:(unsigned int)autosizingMask;
{
    OBASSERT( (autosizingMask & (NSViewHeightSizable|NSViewWidthSizable)) != 0 );
    
    NSRect bounds = [self bounds];
    
    NSRect tallBounds = bounds;
    
    if (autosizingMask & NSViewHeightSizable)
        tallBounds.size.height = FLT_MAX;
    if (autosizingMask & NSViewWidthSizable)
        tallBounds.size.width = FLT_MAX;
    
    NSSize size = [[self cell] cellSizeForBounds:tallBounds];
    
    if (!(autosizingMask & NSViewWidthSizable))
        size.width = bounds.size.width;
    if (!(autosizingMask & NSViewHeightSizable))
        size.height = bounds.size.height;
    
    NSSize frameSize = [self convertSize:size toView:[self superview]];
    
    return frameSize;
}

@end
