// Copyright 2013-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

/*
 These edits are relative to the local snapshot of a document. We cannot stop incoming user edits in all cases and we cannot stop incoming server edits in all cases, but we can and must serialize how we update our database of snapshots. For example, we might have a document open with unsaved local changes when we notice that the server has a newer copy. We might also go offline before we get a chance to fully download that update, so we may want to persist that our local published document is newer than our snapshot AND that the server version is newer. In this case, we probably have an impending conflict. There maybe be some cases of this that we can resolve automatically (for example, if we download the new version from the server and see that it was just a rename while our local changes were content edits).
 
 Some of the options below won't make sense for the remote side. For example, we don't know that a remote document has been renamed until we download its snapshot. We also will likely not use OFXEditTypeDeleted for the remote side but will just process it locally (though maybe we'd want to to deal with local-edit vs. remote-delete conflict).
 
 Some combinations of flags also make no sense. If a file is deleted, then its content edits from that same source don't really matter (and if it was unknown by the peer, it can be silently forgotten).
 */

@interface OFXFileState : NSObject

// Constructors for new starting states
+ (instancetype)missing;
+ (instancetype)normal;
+ (instancetype)edited;
+ (instancetype)deleted;

@property(nonatomic,readonly) BOOL normal;  // The file is present and has not been munged in any way.
@property(nonatomic,readonly) BOOL missing; // This source has never heard of this document. This should be matched with a "normal" on the other source.
@property(nonatomic,readonly) BOOL edited;  // This source has a newer version of the document than what is represented by the snapshot.
@property(nonatomic,readonly) BOOL deleted; // This source has deleted the document and wishes the snapshot would go away and leave it alone.


@property(nonatomic,readonly) BOOL userMoved;   // This source has moved the document to a new relative path than what the snapshot indicates it prefers.
@property(nonatomic,readonly) BOOL autoMoved;   // This source has moved the document to a new relative path than what the snapshot indicates it prefers.

@property(nonatomic,readonly) BOOL onlyAutoMoved; // Normal except for also being -autoMoved (as opposed to auto-moved and edited)

- (instancetype)withEdited; // Transition to the normal state to edited, or moved to moved and edited. Shouldn't be called unless the receiver is normal|moved
- (instancetype)withUserMoved; // As above, but adding in moved.
- (instancetype)withAutoMoved; // As above, but adding in moved.
- (instancetype)withAutoMovedCleared; // For when we have resolved an automatic move and no longer need it

// Archiving
+ (instancetype)stateFromArchiveString:(NSString *)string;
@property(nonatomic,readonly) NSString *archiveString;

@end
