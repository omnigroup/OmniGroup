// Copyright 2004-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import "OAToolbar.h"

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <OmniBase/rcsid.h>

RCS_ID("$Id$");

@implementation OAToolbar

- (void)setVisible:(BOOL)visible;
{
    if (visible == [self isVisible])
	return;
    
    _isUpdatingVisible = YES;
    _updatingVisible = visible;
    id delegate = [self delegate];
    
    @try {
        if ([delegate respondsToSelector:@selector(toolbar:willSetVisible:)])
            [delegate toolbar:self willSetVisible:visible];
        [super setVisible:visible];
    } @finally {
        _isUpdatingVisible = NO;
    }
    
    if ([delegate respondsToSelector:@selector(toolbar:didSetVisible:)])
        [delegate toolbar:self didSetVisible:visible];
}

- (void)setDisplayMode:(NSToolbarDisplayMode)displayMode;
{
    if (displayMode == [self displayMode])
        return;

    _isUpdatingDisplayMode = YES;
    _updatingDisplayMode = displayMode;
    id delegate = [self delegate];

    @try {
        if ([delegate respondsToSelector:@selector(toolbar:willSetDisplayMode:)])
            [delegate toolbar:self willSetDisplayMode:displayMode];
        [super setDisplayMode:displayMode];
    } @finally {
        _isUpdatingDisplayMode = NO;
    }
    
    if ([delegate respondsToSelector:@selector(toolbar:didSetDisplayMode:)])
        [delegate toolbar:self didSetDisplayMode:displayMode];
}

- (void)setSizeMode:(NSToolbarSizeMode)sizeMode;
{
    if (sizeMode == [self sizeMode])
        return;

    _isUpdatingSizeMode = YES;
    _updatingSizeMode = sizeMode;
    id delegate = [self delegate];

    @try {
        if ([delegate respondsToSelector:@selector(toolbar:willSetSizeMode:)])
            [delegate toolbar:self willSetSizeMode:sizeMode];
        [super setSizeMode:sizeMode];
    } @finally {
        _isUpdatingSizeMode = NO;
    }

    if ([delegate respondsToSelector:@selector(toolbar:didSetSizeMode:)])
        [delegate toolbar:self didSetSizeMode:sizeMode];
}

/*" Returns the size that the tool is planning on being.  If the toolbar is in the middle of a resize operation, this will return the planned size.  Otherwise, this will return the current size.  This is useful for resizing toolbar items that have custom views.  It can be hard (impossible?) to do this without flickering; an approach that works is to implement -toolbar:willSetSizeMode: to remove any such existing toolbar item and then recreate it with -insertItemWithItemIdentifier:atIndex:.  Inside our toolbar delegate -toolbar:itemForItemIdentifier:willBeInsertedIntoToolbar: simply use -updatingSizeMode when setting up the custom view. "*/
- (NSToolbarSizeMode)updatingSizeMode;
{
    return _isUpdatingSizeMode ? _updatingSizeMode : [self sizeMode];
}

- (NSToolbarDisplayMode)updatingDisplayMode;
{
    return _isUpdatingDisplayMode ? _updatingDisplayMode : [self displayMode];
}

- (BOOL)updatingVisible;
{
    return _isUpdatingVisible ? _updatingVisible : [self isVisible];
}

@end
