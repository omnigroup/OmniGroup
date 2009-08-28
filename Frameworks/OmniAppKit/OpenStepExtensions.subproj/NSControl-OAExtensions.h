// Copyright 1998-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <AppKit/NSControl.h>
#import <Foundation/NSDate.h>

@class NSMutableDictionary;

@interface NSControl (OAExtensions)

+ (NSTimeInterval)doubleClickDelay;

- (void)setCharacterWrappingStringValue:(NSString *)string;
- (NSMutableDictionary *)attributedStringDictionaryWithCharacterWrapping;

- (void)setStringValueIfDifferent:(NSString *)newString;

- (CGFloat)cgFloatValue;

- (void)sizeToFitVertically;
- (NSSize)desiredFrameSize:(unsigned int)autosizingMask;

@end
