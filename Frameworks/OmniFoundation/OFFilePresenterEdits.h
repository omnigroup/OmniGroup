// Copyright 2010-2013 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <Foundation/NSObject.h>

/*
 A helper object for file presenters.
 
 NSFilePresenters can get signaled about edits in a variety of overs with some redundant notifications. In particular, a file presenter can get told about a change via -presentedItemDidChange/-presentedItemDidMoveToURL:/-accommodatePresentedItemDeletionWithCompletionHandler:, OR it can get told to relinquish to a writer and then told about multiple edits. If a delete happens, then any other edits/moves probably aren't interesting and they shouldn't be acted on until the presenter reacquires control anyway. This class helps buffer up edits until it is appropriate to handle them.
 
 Radar 10879451 describes the oddity of getting told about a change/move after a delete.
 Radar 12455224 describes some scenarios where a presenters can get told about changes made to it when it was the file presenter passed to NSFileCoordinator (which should not receive the notifications).
 
 The normal usage pattern for this is that a presenter would have a 'edits' property pointing to an instance of this class if it is in the middle of -relinquishPresentedItemToWriter:.
 */

typedef void (^OFFilePresenterEditMoveHandler)(id presenter, NSURL *originalURL);
typedef void (^OFFilePresenterEditHandler)(id presenter);

@interface OFFilePresenterEdits : NSObject

- initWithFileURL:(NSURL *)fileURL;

@property(nonatomic,readonly) NSURL *fileURL;

- (void)presenter:(id)presenter relinquishToWriter:(void (^)(void (^reacquirer)(void)))writer;

// Call if you want to discard the presenter, but doing so while it is in the middle of -relinquishPresentedItemToWriter:
- (void)presenter:(id)presenter invalidateAfterWriter:(OFFilePresenterEditHandler)handler;

// Set in -accommodatePresentedItemDeletionWithCompletionHandler:
- (void)presenter:(id)presenter accommodateDeletion:(OFFilePresenterEditHandler)handler;
@property(nonatomic,readonly) BOOL hasAccommodatedDeletion;

// Call from -presentedItemDidChange. Will call the handler immediately unless the receiver is relinquished to a writer, in the most recenly passed handler will be called when reacquiring. NOTE: NSFileCoordinator will sometimes spam us with extra -presentedItemDidChange messages. This class doesn't attempt to ignore them (which is difficult since the file modification date might not advance if the edit is fast enough).
- (void)presenter:(id)presenter changed:(OFFilePresenterEditHandler)handler;

- (void)presenter:(id)presenter didMoveFromURL:(NSURL *)originalURL toURL:(NSURL *)destinationURL handler:(OFFilePresenterEditMoveHandler)handler;

@end
