// Copyright 2010-2012 The Omni Group. All rights reserved.
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
@property(nonatomic,copy) NSDate *originalDate;
@end

#if 1 && defined(DEBUG)
    #define DEBUG_EDITS(format, ...) NSLog(@"EDITS %@: " format, [self shortDescription], ## __VA_ARGS__)
#else
    #define DEBUG_EDITS(format, ...)
#endif


@implementation OFFilePresenterEdits
{
    NSDate *_modificationDate;
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
    
    __block NSDictionary *attributes;
    __block NSError *error;
    
    NSFileCoordinator *coordinator = [[NSFileCoordinator alloc] initWithFilePresenter:nil];
    [coordinator coordinateReadingItemAtURL:_fileURL options:NSFileCoordinatorReadingWithoutChanges error:&error byAccessor:^(NSURL *newURL) {
        attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:[[newURL absoluteURL] path] error:&error];
    }];
    
    if (!attributes) {
        if ([error hasUnderlyingErrorDomain:NSPOSIXErrorDomain code:ENOENT] ||
            [error hasUnderlyingErrorDomain:NSCocoaErrorDomain code:NSFileNoSuchFileError]) {
            // Maybe we are just creating the file.
        } else {
            NSLog(@"Error looking up attributes of %@: %@", _fileURL, [error toPropertyList]);
        }
    }
    _modificationDate = attributes[NSFileModificationDate];

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

    // File coordination can send spurious extra -presentedItemDidChange notifications. Ignore them.
    if (_modificationDate) {
        // TODO: We are on the presenter queue of our owner here -- we don't do file coordination here (if we did we'd need our owner passed in to pass to the file coordinator to avoid deadlock).
        NSError *error;
        NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:[[_fileURL absoluteURL] path] error:&error];
        
        NSDate *modificationDate = attributes[NSFileModificationDate];
        if (OFISEQUAL(_modificationDate, modificationDate)) {
            OBFinishPortingLater("This assumes that we always to full-package replacement rather than writing a deeply nested sub-item w/in a package");
            DEBUG_EDITS(@"  Ignoring spurious change notification -- modification date has not changed");
            return;
        }
    }
    
    if (!handler)
        // Note that the edit happened w/o any caller-requested action
        handler = ^(id _presenter){};
    
    if (_relinquishedToWriter) {
        DEBUG_EDITS(@"  Inside writer; delay handling change");
        self.changed = handler;
    } else
        handler(presenter);
}

- (void)presenter:(id)presenter didMoveFromURL:(NSURL *)originalURL date:(NSDate *)originalDate toURL:(NSURL *)destinationURL handler:(OFFilePresenterEditMoveHandler)handler;
{
    OBPRECONDITION(self.moved == nil);
    OBPRECONDITION(handler != nil);
    OBPRECONDITION(originalURL != nil);
    OBPRECONDITION(originalDate != nil);
    OBPRECONDITION(_originalURL == nil);
    OBPRECONDITION(_originalDate == nil);
    OBPRECONDITION([_fileURL isEqual:originalURL]);
    OBPRECONDITION([originalDate isEqual:_modificationDate]);
    
    DEBUG_EDITS(@"  Inside writer; delay handling move");
    if (!handler)
        // Note that the edit happened w/o any caller-requested action
        handler = ^(id _presenter, NSURL *_originalURL, NSDate *_originalDate){};
    
    _fileURL = [destinationURL copy];
    
    if (_relinquishedToWriter) {
        self.moved = handler;
        
        _originalURL = [originalURL copy];
        
        _originalDate = [originalDate copy];
    } else {
        handler(presenter, originalURL, originalDate);
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
                OBASSERT(_originalDate != nil);
                NSURL *oldURL = _originalURL;
                _originalURL = nil;
                NSDate *oldDate = _originalDate;
                _originalDate = nil;
                
                moved(presenter, oldURL, oldDate);
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

- (void)updateModificationDate;
{
    NSError *error;
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:[[_fileURL absoluteURL] path] error:&error];
    if (!attributes) {
        NSLog(@"Error getting attributes of %@: %@", _fileURL, [error toPropertyList]);
        return;
    }

    _modificationDate = attributes[NSFileModificationDate];
}

- (NSString *)shortDescription;
{
    return [NSString stringWithFormat:@"deleted:%d changed:%d moved:%d", (_deleted != nil), (_changed != nil), (_moved != nil)];
}

@end
