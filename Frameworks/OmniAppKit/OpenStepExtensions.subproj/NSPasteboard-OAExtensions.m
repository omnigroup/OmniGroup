// Copyright 1997-2015 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniAppKit/NSPasteboard-OAExtensions.h>

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <OmniBase/OmniBase.h>
#import <OmniFoundation/OmniFoundation.h>

RCS_ID("$Id$")

@implementation NSPasteboard (OAExtensions)

- (NSParagraphStyle *)paragraphStyleForType:(NSString *)type;
{
    NSAttributedString *attributedString = [[[NSAttributedString alloc] initWithRTF:[self dataForType:type] documentAttributes:NULL] autorelease];
    if ([attributedString length] == 0)
        return nil;
    return [attributedString attribute:NSParagraphStyleAttributeName atIndex:0 effectiveRange:NULL];
}

- (BOOL)setParagraphStyle:(NSParagraphStyle *)paragraphStyle forType:(NSString *)type;
{
    if (paragraphStyle == nil)
        return NO;
    NSDictionary *attributes = [NSDictionary dictionaryWithObject:paragraphStyle forKey:NSParagraphStyleAttributeName];
    NSMutableAttributedString *attributedString = [[[NSMutableAttributedString alloc] initWithString:@" " attributes:attributes] autorelease];
    return [self setData:[attributedString RTFFromRange:NSMakeRange(0,[attributedString length]) documentAttributes:@{}] forType:type];
}

@end
