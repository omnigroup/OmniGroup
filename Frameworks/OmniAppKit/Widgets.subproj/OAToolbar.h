// Copyright 2004-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniAppKit/Widgets.subproj/OAToolbar.h 71191 2005-12-15 22:25:26Z bungi $

#import <AppKit/NSToolbar.h>

@interface OAToolbar : NSToolbar
{
    BOOL _isUpdatingVisible;
    BOOL _updatingVisible;

    BOOL                 _isUpdatingDisplayMode;
    NSToolbarDisplayMode _updatingDisplayMode;
    
    BOOL              _isUpdatingSizeMode;
    NSToolbarSizeMode _updatingSizeMode;
}

- (NSToolbarDisplayMode)updatingDisplayMode;
- (NSToolbarSizeMode)updatingSizeMode;
- (BOOL)updatingVisible;

@end

@interface NSObject (OAToolbarDelegate)
- (void)toolbar:(OAToolbar *)aToolbar willSetVisible:(BOOL)visible;
- (void)toolbar:(OAToolbar *)aToolbar didSetVisible:(BOOL)visible;
- (void)toolbar:(OAToolbar *)aToolbar willSetDisplayMode:(NSToolbarDisplayMode)displayMode;
- (void)toolbar:(OAToolbar *)aToolbar didSetDisplayMode:(NSToolbarDisplayMode)displayMode;
- (void)toolbar:(OAToolbar *)aToolbar willSetSizeMode:(NSToolbarSizeMode)sizeMode;
- (void)toolbar:(OAToolbar *)aToolbar didSetSizeMode:(NSToolbarSizeMode)sizeMode;
@end
