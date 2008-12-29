// Copyright 1997-2005 Omni Development, Inc.  All rights reserved.
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

- (NSData *)dataForType:(NSString *)dataType stripTrailingNull:(BOOL)stripNull;
{
    NSData                     *data;

    if (!dataType)
	return nil;
    if (!(data = [self dataForType:dataType]))
	return nil;
    if (stripNull) {
        const char *bytes;
        int length;

	length = [data length];
	bytes = (const char *)[data bytes];
	if (bytes[length - 1] == '\0')
		data = [data subdataWithRange: NSMakeRange(0, length - 1)];
    }	       

    return data;
}

- (NSParagraphStyle *)paragraphStyleForType:(NSString *)type;
{
    NSAttributedString *attributedString = [[[NSAttributedString alloc] initWithRTF:[self dataForType:type] documentAttributes:NULL] autorelease];
    if ([attributedString length] == 0) {
        return nil;
    }
    return [attributedString attribute:NSParagraphStyleAttributeName atIndex:0 effectiveRange:NULL];
}

- (BOOL)setParagraphStyle:(NSParagraphStyle *)paragraphStyle forType:(NSString *)type;
{
    NSDictionary *attributes;
    NSMutableAttributedString *attributedString;

    if (paragraphStyle == nil)
        return NO;
    attributes = [NSDictionary dictionaryWithObject:paragraphStyle forKey:NSParagraphStyleAttributeName];
    attributedString = [[[NSMutableAttributedString alloc] initWithString:@" " attributes:attributes] autorelease];
    return [self setData:[attributedString RTFFromRange:NSMakeRange(0,[attributedString length]) documentAttributes:nil] forType:type];
}

@end
