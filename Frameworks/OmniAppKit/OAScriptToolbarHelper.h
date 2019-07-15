// Copyright 2002-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/NSObject.h>

#import <OmniAppKit/OAToolbarWindowController.h>

NS_ASSUME_NONNULL_BEGIN

@class OAToolbarItem;

@interface OAScriptToolbarHelper : NSObject <OAToolbarHelper>

+ (void)setDisabled:(BOOL)disabled;

@end

@protocol OAScriptToolbarHelperDelegate
@optional
- (BOOL)scriptToolbarItemShouldExecute:(OAToolbarItem *)item;
- (void)scriptToolbarItemFinishedExecuting:(OAToolbarItem *)item; // might be success, might be failure.
- (NSAppleEventDescriptor *)scriptToolbarItemArguments:(OAToolbarItem *)item; // returns a list of arguments to be passed to the invoked script (by default, a single-item list containing the receiver's window)
@end

@interface OAToolbarWindowController (OAScriptToolbarHelperExtensions) <OAScriptToolbarHelperDelegate>
@end

NS_ASSUME_NONNULL_END

