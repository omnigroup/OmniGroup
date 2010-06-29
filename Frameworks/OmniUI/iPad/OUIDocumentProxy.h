// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <OmniFoundation/OFObject.h>

@class OUIDocumentPreviewLoadOperation, OUIDocumentProxyView;
@protocol OUIDocumentPreview;

@interface OUIDocumentProxy : OFObject
{
@private
    NSURL *_url;
    NSDate *_date;
    BOOL _selected;
    BOOL _layoutShouldAdvance;
    id _target;
    SEL _action;
    CGRect _frame;
    CGRect _previousFrame;
    
    OUIDocumentProxyView *_view;
    id <OUIDocumentPreview> _preview;
    
    OUIDocumentPreviewLoadOperation *_previewLoadOperation;
    BOOL _hasRetriedProxyDueToIncorrectSize;
}

- initWithURL:(NSURL *)url;

- (void)invalidate;

@property(readonly) NSURL *url;
@property(readonly) NSData *emailData; // packages cannot currently be emailed, so this allows subclasses to return a different content for email

@property(retain,nonatomic) id target;
@property(assign,nonatomic) SEL action;

@property(assign,nonatomic) CGRect frame;
@property(readonly) CGRect previousFrame;

@property(copy) NSDate *date;
@property(retain,nonatomic) OUIDocumentProxyView *view;

- (NSString *)name;
- (void)refreshDateAndPreview;
- (CGSize)previewSizeForTargetSize:(CGSize)targetSize;

@property(readonly) BOOL hasPDFPreview;
@property(readonly) BOOL isLoadingPreview;
@property(assign,nonatomic) BOOL layoutShouldAdvance; // Stack the next proxy on top of this one during layout?

@property(assign,nonatomic) BOOL selected;

- (NSComparisonResult)compare:(OUIDocumentProxy *)otherProxy;

// Either input can be NULL if the caller doesn't care about that value. But, sometimes we want both and it is more efficient to get both at once.
+ (BOOL)getPDFPreviewData:(NSData **)outPDFData modificationDate:(NSDate **)outModificationDate fromURL:(NSURL *)url error:(NSError **)outError;

@end

extern NSString * const OUIDocumentProxyPreviewDidLoadNotification;
extern void OUIDocumentProxySplitNameAndCounter(NSString *originalName, NSString **outName, NSUInteger *outCounter);
