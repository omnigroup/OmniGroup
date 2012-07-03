// Copyright 2005-2007, 2010, 2012 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <AppKit/NSButtonCell.h>

extern NSString *TabTitleDidChangeNotification;

@interface OITabCell : NSButtonCell
{
    BOOL duringMouseDown;
    NSInteger oldState;
    BOOL dimmed;
    BOOL isPinned;
    NSImage *grayscaleImage;
    NSImage *dimmedImage;
    NSImageCell *_imageCell;
}

- (BOOL)duringMouseDown;
- (void)saveState;
- (void)clearState;
- (void)setDimmed:(BOOL)value;
- (BOOL)dimmed;
- (BOOL)isPinned;
- (void)setIsPinned:(BOOL)newValue;
- (BOOL)drawState;

@end
