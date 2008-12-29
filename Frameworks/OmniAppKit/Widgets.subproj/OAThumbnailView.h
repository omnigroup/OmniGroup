// Copyright 1997-2005 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Header: svn+ssh://source.omnigroup.com/Source/svn/Omni/tags/OmniSourceRelease/2008-09-09/OmniGroup/Frameworks/OmniAppKit/Widgets.subproj/OAThumbnailView.h 68913 2005-10-03 19:36:19Z kc $

#import <AppKit/NSView.h>

@class OAThumbnailView;


@protocol OAThumbnailProvider
- (unsigned int) thumbnailCount;

- (NSImage *)thumbnailImageAtIndex: (unsigned int) thumbnailIndex;
- (void)missedThumbnailImageInView: (OAThumbnailView *)view
                              rect: (NSRect)rect
                           atIndex: (unsigned int) thumbnailIndex;
- (NSSize)thumbnailSizeAtIndex: (unsigned int) thumbnailIndex;
- (void)thumbnailWasSelected:(NSEvent *)event
                     atIndex: (unsigned int) thumbnailIndex;
- (BOOL)isThumbnailSelectedAtIndex: (unsigned int) thumbnailIndex;
@end

@interface OAThumbnailView : NSView
{
    NSObject <OAThumbnailProvider> *provider;

    NSSize	 maximumThumbnailSize;
    NSSize	 padding;
    unsigned int columnCount, rowCount;
    NSSize	 cellSize;
    float	 horizontalMargin;
    
    BOOL	 thumbnailsAreNumbered;
}

- (void)scrollSelectionToVisible;

- (void)setThumbnailProvider:(NSObject <OAThumbnailProvider> *) newThumbnailsProvider;
- (NSObject <OAThumbnailProvider> *)thumbnailProvider;

- (void)sizeToFit;

- (void)setThumbnailsNumbered:(BOOL)newThumbnailsAreNumbered;
- (BOOL)thumbnailsAreNumbered;

- (void)drawMissingThumbnailRect:(NSRect)rect;

@end


