// Copyright 1997-2005, 2007-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/NSTextField-OAExtensions.h>

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

#import <OmniAppKit/NSControl-OAExtensions.h>

RCS_ID("$Id$")

@implementation NSTextField (OAExtensions)

- (void) setStringValueAllowingNil: (NSString *) aString;
{
    if (!aString)
        aString = @"";
    [self setStringValue: aString];
}

- (void)appendString:(NSString *)aString;
{
    [self setStringValue:[NSString stringWithFormat:@"%@%@",
	    [self stringValue], aString]];
}

- (void)changeColorAsIfEnabledStateWas:(BOOL)newEnabled;
{
    [self setTextColor:newEnabled ? [NSColor controlTextColor] : [NSColor disabledControlTextColor]];
}

// Subclassed from NSControl-OAExtensions

- (NSMutableDictionary *)attributedStringDictionaryWithCharacterWrapping;
{
    NSMutableDictionary *attributes;

    attributes = [super attributedStringDictionaryWithCharacterWrapping];
    [attributes setObject:[self textColor] forKey:NSForegroundColorAttributeName];

    return attributes;
}

@end
