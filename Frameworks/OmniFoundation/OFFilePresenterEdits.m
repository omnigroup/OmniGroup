// Copyright 2010-2013 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFFilePresenterEdits.h>

#import <Foundation/NSFileCoordinator.h>

#if !defined(OB_ARC) || !OB_ARC
    #error This file should be compiled with ARC enabled
#endif

@interface OFFilePresenterEdits ()
@property(nonatomic,copy) OFFilePresenterEditHandler invalidateAfterWriter;
@property(nonatomic,copy) OFFilePresenterEditHandler changed;
@property(nonatomic,copy) OFFilePresenterEditHandler deleted;
@property(nonatomic,copy) OFFilePresenterEditMoveHandler moved;
@property(nonatomic,copy) NSURL *originalURL;
@end

#if 0 && defined(DEBUG)
    #define DEBUG_EDITS(format, ...) NSLog(@"EDITS %@: " format, [self shortDescription], ## __VA_ARGS__)
#else
    #define DEBUG_EDITS(format, ...)
#endif


@implementation OFFilePresenterEdits
{
    BOOL _relinquishedToWriter;
}

- init;
{
    OBRejectUnusedImplementation(self, _cmd);
}

// This should be called after the presenter that owns us has registered for file presentation (so any edits will invoke a -presentedItemDidChange, thus calling back to us to update our date)
- initWithFileURL:(NSURL *)fileURL;
{
    if (!(self = [super init]))
        return nil;
    
    _fileURL = [fileURL copy];
    
    return self;
}

- (void)dealloc;
{
    OBPRECONDITION(_relinquishedToWriter == NO);
}

- (void)presenter:(id)presenter invalidateAfterWriter:(OFFilePresenterEditHandler)handler;
{
    OBPRECONDITION(handler); // This isn't a file presenter state, but a request by the caller -- they need to give us something to call
    OBPRECONDITION(self.invalidateAfterWriter == nil);
    
    if (_relinquishedToWriter) {
        DEBUG_EDITS(@"  Inside writer; delay invalidation");
        self.invalidateAfterWriter = handler;
    } else
        handler(presenter);
}

- (void)presenter:(id)presenter accommodateDeletion:(OFFilePresenterEditHandler)handler;
{
    OBPRECONDITION(_relinquishedToWriter == YES);
    OBPRECONDITION(_deleted == nil);

    if (!handler)
        // Note that the deletion happened w/o any caller-requested action
        handler = ^(id _presenter){};

    if (_relinquishedToWriter) {
        DEBUG_EDITS(@"  Inside writer; delay handling deletion");
        self.deleted = handler;
    } else {
        OBASSERT_NOT_REACHED("Deletions should always be signaled from inside -accommodatePresentedItemDeletionWithCompletionHandler:");
        handler(presenter);
    }
}

- (BOOL)hasAccommodatedDeletion;
{
    return _deleted != nil;
}

- (void)presenter:(id)presenter changed:(OFFilePresenterEditHandler)handler;
{
    // NSFilePresenters get spammed with change notifications. We'll assume that the handler is the same in each case (so we coalesce them into whatever the last call is).
    //OBPRECONDITION(self.changed == nil);
    
    if (!handler)
        // Note that the edit happened w/o any caller-requested action
        handler = ^(id _presenter){};
    
    if (_relinquishedToWriter) {
        DEBUG_EDITS(@"  Inside writer; delay handling change");
        self.changed = handler;
    } else
        handler(presenter);
}

- (void)presenter:(id)presenter didMoveFromURL:(NSURL *)originalURL toURL:(NSURL *)destinationURL handler:(OFFilePresenterEditMoveHandler)handler;
{
    OBPRECONDITION(self.moved == nil);
    OBPRECONDITION(handler != nil);
    OBPRECONDITION(originalURL != nil);
    OBPRECONDITION(_originalURL == nil);
    OBPRECONDITION([_fileURL isEqual:originalURL]);
    
    DEBUG_EDITS(@"  Inside writer; delay handling move");
    if (!handler)
        // Note that the edit happened w/o any caller-requested action
        handler = ^(id _presenter, NSURL *_originalURL){};
    
    _fileURL = [destinationURL copy];
    
    if (_relinquishedToWriter) {
        self.moved = handler;
        
        _originalURL = [originalURL copy];
    } else {
        handler(presenter, originalURL);
    }
}

- (void)presenter:(id)presenter relinquishToWriter:(void (^)(void (^reacquirer)(void)))writer;
{
    OBPRECONDITION(_relinquishedToWriter == NO);
    
    DEBUG_EDITS(@"-relinquishPresentedItemToWriter:");

    _relinquishedToWriter = YES;
    writer(^{
        DEBUG_EDITS(@"Reacquiring after writer, edits %@", [self shortDescription]);

        OBASSERT(_relinquishedToWriter == YES);
        _relinquishedToWriter = NO;

        if (_deleted) {
            // Ignore these edits -- our file has sailed into the west.
            self.changed = nil;
            self.moved = nil;
            
            OFFilePresenterEditHandler deleted = _deleted;
            _deleted = nil;
            deleted(presenter);
        } else {
            if (_moved) {
                OFFilePresenterEditMoveHandler moved = _moved;
                _moved = nil;
                
                OBASSERT(_originalURL != nil);
                NSURL *oldURL = _originalURL;
                _originalURL = nil;
                
                moved(presenter, oldURL);
            }
            
            if (_changed) {
                OFFilePresenterEditHandler changed = _changed;
                _changed = nil;
                changed(presenter);
            }
        }
        
        if (_invalidateAfterWriter) {
            OFFilePresenterEditHandler invalidate = _invalidateAfterWriter;
            _invalidateAfterWriter = nil;
        
            invalidate(presenter);
        }
    });
}

- (NSString *)shortDescription;
{
    return [NSString stringWithFormat:@"deleted:%d changed:%d moved:%d", (_deleted != nil), (_changed != nil), (_moved != nil)];
}

@end
