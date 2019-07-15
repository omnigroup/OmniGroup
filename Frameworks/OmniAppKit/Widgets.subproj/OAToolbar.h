// Copyright 2004-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

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

@property (nonatomic, readonly) NSWindow *window; // Asks delegate. This is for toolbar items that are text-only and need to validate based on firstResponder.

@end

@protocol OAToolbarDelegate <NSToolbarDelegate>
@optional
- (void)toolbar:(OAToolbar *)aToolbar willSetVisible:(BOOL)visible;
- (void)toolbar:(OAToolbar *)aToolbar didSetVisible:(BOOL)visible;
- (void)toolbar:(OAToolbar *)aToolbar willSetDisplayMode:(NSToolbarDisplayMode)displayMode;
- (void)toolbar:(OAToolbar *)aToolbar didSetDisplayMode:(NSToolbarDisplayMode)displayMode;
- (void)toolbar:(OAToolbar *)aToolbar willSetSizeMode:(NSToolbarSizeMode)sizeMode;
- (void)toolbar:(OAToolbar *)aToolbar didSetSizeMode:(NSToolbarSizeMode)sizeMode;
- (BOOL)toolbar:(OAToolbar *)aToolbar shouldSelectToolbarItemWithIdentifier:(NSString *)itemIdentifier;

@property (nonatomic, readonly) NSWindow *window;

@end
