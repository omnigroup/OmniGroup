// Copyright 2007-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <AppKit/NSWindowController.h>

@class NSArrayController, NSButton, NSImageView, NSProgressIndicator, NSSplitView, NSTableView, NSTextField;
@class WebView;
@class OSUItem;

extern NSString * const OSUAvailableUpdateControllerAvailableItemsBinding;
extern NSString * const OSUAvailableUpdateControllerCheckInProgressBinding;
extern NSString * const OSUAvailableUpdateControllerLastCheckFailedBinding;
extern NSString * const OSUAvailableUpdateControllerLastCheckUserInitiatedBinding;

@interface OSUAvailableUpdateController : NSWindowController <NSTableViewDelegate>

+ (OSUAvailableUpdateController *)availableUpdateController:(BOOL)shouldCreate;

- (IBAction)installSelectedItem:(id)sender;
- (IBAction)ignoreSelectedItem:(id)sender;
- (IBAction)ignoreCertainTracks:(id)sender;
- (IBAction)showMoreInformation:(id)sender;

// KVC
- (OSUItem *)selectedItem;
- (NSString *)ignoreTrackItemTitle;

@end
