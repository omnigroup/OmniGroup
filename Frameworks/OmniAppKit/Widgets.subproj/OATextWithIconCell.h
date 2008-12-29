// Copyright 2001-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniAppKit/Widgets.subproj/OATextWithIconCell.h 68913 2005-10-03 19:36:19Z kc $

#import <AppKit/NSTextFieldCell.h>

@interface OATextWithIconCell : NSTextFieldCell
{
    NSImage *icon;
    struct {
        unsigned int drawsHighlight:1;
        unsigned int imagePosition:3;
        unsigned int settingUpFieldEditor:1;
    } _oaFlags;
}

// API
- (NSImage *)icon;
- (void)setIcon:(NSImage *)anIcon;

- (NSCellImagePosition)imagePosition;
- (void)setImagePosition:(NSCellImagePosition)aPosition;

- (BOOL)drawsHighlight;
- (void)setDrawsHighlight:(BOOL)flag;

- (NSRect)textRectForFrame:(NSRect)cellFrame inView:(NSView *)controlView;

@end

#import "FrameworkDefines.h"

// Use as keys into an NSDIctionary when you call -setObjectValue: on this cell, or a dictionary you build and return in a tableView dataSource's -objectValue:forItem:row: method.
OmniAppKit_EXTERN NSString *OATextWithIconCellStringKey;
OmniAppKit_EXTERN NSString *OATextWithIconCellImageKey;
