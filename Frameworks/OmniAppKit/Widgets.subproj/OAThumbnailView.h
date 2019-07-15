// Copyright 1997-2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <AppKit/NSView.h>

@class OAThumbnailView;


@protocol OAThumbnailProvider
- (NSUInteger) thumbnailCount;

- (NSImage *)thumbnailImageAtIndex:(NSUInteger)thumbnailIndex;
- (void)missedThumbnailImageInView:(OAThumbnailView *)view rect:(NSRect)rect atIndex:(NSUInteger)thumbnailIndex;
- (NSSize)thumbnailSizeAtIndex: (NSUInteger) thumbnailIndex;
- (void)thumbnailWasSelected:(NSEvent *)event atIndex:(NSUInteger) thumbnailIndex;
- (BOOL)isThumbnailSelectedAtIndex:(NSUInteger)thumbnailIndex;
@end

@interface OAThumbnailView : NSView
{
    NSObject <OAThumbnailProvider> *provider;

    NSSize maximumThumbnailSize;
    NSSize padding;
    NSUInteger columnCount, rowCount;
    NSSize cellSize;
    CGFloat horizontalMargin;
    
    BOOL thumbnailsAreNumbered;
}

- (void)scrollSelectionToVisible;

- (void)setThumbnailProvider:(NSObject <OAThumbnailProvider> *) newThumbnailsProvider;
- (NSObject <OAThumbnailProvider> *)thumbnailProvider;

- (void)sizeToFit;

- (void)setThumbnailsNumbered:(BOOL)newThumbnailsAreNumbered;
- (BOOL)thumbnailsAreNumbered;

- (void)drawMissingThumbnailRect:(NSRect)rect;

@end


