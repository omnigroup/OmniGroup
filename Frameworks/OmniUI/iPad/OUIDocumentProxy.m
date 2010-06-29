// Copyright 2010 The Omni Group.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniUI/OUIDocumentProxy.h>

#import <OmniUI/OUIDocumentProxyView.h>
#import <OmniUI/OUIDirectTapGestureRecognizer.h>
#import <OmniUI/OUIAppController.h>
#import <OmniUI/UIView-OUIExtensions.h>
#import <OmniFoundation/NSMutableDictionary-OFExtensions.h>
#import <OmniFoundation/OFPreference.h>
#import <OmniFoundation/NSUserDefaults-OFExtensions.h>
#import "OUIDocumentPDFPreview.h"
#import "OUIDocumentPreviewLoadOperation.h"
#import "OUIDocumentProxy-Internal.h"
#import "OUIDocumentPreview.h"
#import "OUIDocumentImagePreview.h"

RCS_ID("$Id$");

#if 0 && defined(DEBUG)
    #define PREVIEW_DEBUG(format, ...) NSLog(@"PREVIEW: '%@' " format, self.name, ## __VA_ARGS__)
#else
    #define PREVIEW_DEBUG(format, ...)
#endif

NSString * const OUIDocumentProxyPreviewDidLoadNotification = @"OUIDocumentProxyPreviewDidLoadNotification";

// If the proxy name ends in a number, we are likely dealing with a duplicate.
void OUIDocumentProxySplitNameAndCounter(NSString *originalName, NSString **outName, NSUInteger *outCounter)
{
    NSString *name = originalName;
    NSUInteger counter = 0;
    NSRange notNumberRange = [name rangeOfCharacterFromSet:[[NSCharacterSet decimalDigitCharacterSet] invertedSet] options:NSBackwardsSearch];
    
    // Has at least one digit at the end and isn't all digits?
    if (notNumberRange.length > 0 && NSMaxRange(notNumberRange) < [name length]) {
        // Is there a space before the digits?
        if ([name characterAtIndex:NSMaxRange(notNumberRange) - 1] == ' ') {
            counter = [[name substringFromIndex:NSMaxRange(notNumberRange)] intValue];
            name = [name substringToIndex:NSMaxRange(notNumberRange) - 1];
        }
    }
    
    *outName = name;
    *outCounter = counter;
}

@interface OUIDocumentProxy (/*Private*/)
- (void)_documentProxyTapped:(UITapGestureRecognizer *)recognizer;
@end

@implementation OUIDocumentProxy

static NSOperationQueue *PreviewLoadOperationQueue = nil;
static OFPreference *ProxyAspectRatioCachePreference;

+ (void)initialize;
{
    OBINITIALIZE;
    
    PreviewLoadOperationQueue = [[NSOperationQueue alloc] init];
    [PreviewLoadOperationQueue setMaxConcurrentOperationCount:1];

    ProxyAspectRatioCachePreference = [[OFPreference preferenceForKey:@"OUIDocumentProxyPreviewAspectRatioByURL"] retain];
}

- initWithURL:(NSURL *)url;
{
    OBPRECONDITION(url);
    OBPRECONDITION([url isFileURL]);
    
    if (!url) {
        [self release];
        return nil;
    }
    
    if (!(self = [super init]))
        return nil;
    
    _url = [[url absoluteURL] copy];
    _frame = CGRectMake(0, 0, 400, 400);
    _layoutShouldAdvance = YES;
    
    [self refreshDateAndPreview];
    
    OBASSERT(!_view); // no way we can get a view or preview by now
    OBASSERT(!_preview);
    OBASSERT(!_previewLoadOperation);

    OBASSERT(_date); // should get a date.
    
    return self;
}

- (void)dealloc;
{
    [_url release];
    [_date release];
    [_target release];
    [_previewLoadOperation cancel];
    [_previewLoadOperation release];
    [_view release];
    [_preview release];
    
    [super dealloc];
}

- (void)invalidate;
{
    if (_view) {
        _view.preview = nil;
        _view.gestureRecognizers = nil; // targets point back to us
        self.view = nil;
    }
    [_target release];
    _target = nil;
    
    [_previewLoadOperation cancel];
    [_previewLoadOperation release];
    _previewLoadOperation = nil;
}

@synthesize url = _url;

- (NSData *)emailData;
{
    return [NSData dataWithContentsOfURL:self.url];
}

@synthesize date = _date;
@synthesize target = _target;
@synthesize action = _action;

@synthesize view = _view;
- (void)setView:(OUIDocumentProxyView *)view;
{
    if (_view == view)
        return;
    
    if (_view) {        
        _view.gestureRecognizers = nil;
        [_view release];
        _view = nil;
    }
    
    if (view) {
        _view = [view retain];
        OUIDirectTapGestureRecognizer *tap = [[OUIDirectTapGestureRecognizer alloc] initWithTarget:self action:@selector(_documentProxyTapped:)];
        [view addGestureRecognizer:tap];
        [tap release];
    
        // TODO: Do this here or in the scroll view layout? Probably in the scrollview layout so that we can animate new proxies on screen right.
        _view.frame = _frame;
        _view.preview = _preview;
        _view.selected = _selected;
        
        [self startPreviewLoadIfNeeded:YES];
    } else {
        // Don't keep the preview around unless the picker view wants us to display (or speculatively display) something. It signals this by giving us a view. No view, no preview.
        [self cancelPreviewLoadIfRunning];
        
        [_preview release];
        _preview = nil;
    }
}

@synthesize frame = _frame;
- (void)setFrame:(CGRect)frame;
{
    OBPRECONDITION(CGRectEqualToRect(frame, CGRectIntegral(frame)));

    if (CGRectEqualToRect(_frame, frame))
        return;

    _previousFrame = _frame;
    _frame = frame;
    
    if (_view) {
        [_view setFrame:frame];

        [self startPreviewLoadIfNeeded:YES];
    }
}

@synthesize previousFrame = _previousFrame;

- (NSString *)name;
{
    return [[[[self url] path] lastPathComponent] stringByDeletingPathExtension];
}

- (void)refreshDateAndPreview;
{
    NSError *error = nil;
    
    // Clear and reload any preview asynchronously
    if (_view) {
        [self startPreviewLoadIfNeeded:NO/*ifNeeded*/];
    }
    
    // We use the file modification date rather than a date embedded inside the file since the latter would cause duplicated documents to not sort to the front as a new document (until you modified them, at which point they'd go flying to the beginning).
    NSDate *date = nil;
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:[[_url absoluteURL] path]  error:&error];
    if (attributes)
        date = [attributes fileModificationDate];
    if (!date)
        date = [NSDate date]; // Default to now if we can't get the attributes or they are bogus for some reason.

    self.date = date;
}

static NSString *_aspectRatioCacheKey(OUIDocumentProxy *self)
{
    OBPRECONDITION(self->_url);
    return [self->_url absoluteString];
}

- (CGSize)previewSizeForTargetSize:(CGSize)targetSize;
{
    OBPRECONDITION([NSThread isMainThread]); // We read the global aspect ratio cache

    NSString *cacheKey = _aspectRatioCacheKey(self);
    
    NSDictionary *aspectRatioCache = [ProxyAspectRatioCachePreference dictionaryValue];
    if (!aspectRatioCache)
        aspectRatioCache = [NSDictionary dictionary]; // make sure we get a non-nil object for the message below
    
    CGFloat aspectRatio = [aspectRatioCache floatForKey:cacheKey defaultValue:-1];
    CGSize size;
    
    if (aspectRatio < 0) {
        // No preview loaded yet. Use the placeholder size.
        UIImage *image = [OUIDocumentProxyView placeholderPreviewImage];
        OBASSERT(image);
        if (image)
            return image.size;
        
        // do something reasonable...
        aspectRatio = 4.0/3.0;
    }
    
    // Aspect radio is w/h. Assume the preview has h=1, then its width is the aspect ratio. We can then figure out the max scale factor in each direction.
    CGFloat previewWidth = aspectRatio;
    CGFloat previewHeight = 1;
    
    CGFloat widthScale = targetSize.width/previewWidth;
    CGFloat heightScale = targetSize.height/previewHeight;
    CGFloat scale = MIN(widthScale, heightScale);
    
    size = CGSizeMake(previewWidth * scale, previewHeight * scale);
    PREVIEW_DEBUG(@"  aspect %f -> %@ for %@", aspectRatio, NSStringFromCGSize(size), cacheKey);
    
    return size;
}

- (BOOL)hasPDFPreview
{
    return [_preview isKindOfClass:[OUIDocumentPDFPreview class]];
}

- (BOOL)isLoadingPreview;
{
    return _previewLoadOperation != nil;
}

@synthesize layoutShouldAdvance = _layoutShouldAdvance;

@synthesize selected = _selected;
- (void)setSelected:(BOOL)selected;
{
    if (_selected == selected)
        return;
    
    _selected = selected;
    _view.selected = selected;
}

- (NSComparisonResult)compare:(OUIDocumentProxy *)otherProxy;
{
    // First, compare dates
    NSComparisonResult dateComparison = [_date compare:otherProxy.date];
    switch (dateComparison) {
        default: case NSOrderedSame:
            break;
        case NSOrderedAscending:
            return NSOrderedDescending; // Newer documents come first
        case NSOrderedDescending:
            return NSOrderedAscending; // Newer documents come first
    }

    // Then compare name and if the names are equal, duplication counters.
    NSString *name1, *name2;
    NSUInteger counter1, counter2;
    
    OUIDocumentProxySplitNameAndCounter(self.name, &name1, &counter1);
    OUIDocumentProxySplitNameAndCounter(otherProxy.name, &name2, &counter2);
    
    

    NSComparisonResult caseInsensitiveCompare = [name1 localizedCaseInsensitiveCompare:name2];
    if (caseInsensitiveCompare != NSOrderedSame)
        return caseInsensitiveCompare; // Sort names into alphabetical order

    // Use the duplication counters, in reverse order ("Foo 2" should be to the left of "Foo").
    if (counter1 < counter2)
        return NSOrderedDescending;
    else if (counter1 > counter2)
        return NSOrderedAscending;
    
    // If all else is equal, compare URLs (maybe different extensions?).  (If those are equal, so are the proxies!)
    return [[_url absoluteString] compare:[otherProxy.url absoluteString]];
 }

+ (BOOL)getPDFPreviewData:(NSData **)outPDFData modificationDate:(NSDate **)outModificationDate fromURL:(NSURL *)url error:(NSError **)outError;
{
    NSDate *date = nil;
    NSData *data = nil;
    
    if (outModificationDate) {
        // Default to the file creation date, but this can be wildly incorrect (particularly in the simulator) since files might have just been copied willy-nilly w/o care for preserving dates. Subclasses may do something smarter like use a date embedded in the file contents.
        NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:[url path]  error:outError];
        if (attributes)
            date = [attributes fileModificationDate];
        if (!date)
            date = [NSDate date]; // Default to now if we can't get the attributes or they are bogus for some reason.
    }
    
    // Only write if there is no error above
    if (outModificationDate)
        *outModificationDate = date;
    if (outPDFData)
        *outPDFData = data;
    
    return YES;
}

#pragma mark -
#pragma mark Internal

- (void)startPreviewLoadIfNeeded:(BOOL)ifNeeded;
{
    OBPRECONDITION([NSThread isMainThread]);

    PREVIEW_DEBUG(@"%s (ifNeeded:%d)", __PRETTY_FUNCTION__, ifNeeded);
    
    if (_previewLoadOperation) {
        PREVIEW_DEBUG(@"  bail -- going already");
        return;
    }
    
    if (!_view) {
        OBASSERT_NOT_REACHED("Don't ask for a preview if you aren't going to show it");
        return;
    }
    
    CGRect bounds = _view.bounds;

    if (ifNeeded) {
        if (_preview) {
            // Already have one, but is it the right size?  We want to keep this preview until we get a good one since it'll be better than the placeholder preview if it did ever get resolved before.
            if (CGSizeEqualToSize(bounds.size, _preview.originalViewSize)) {
                PREVIEW_DEBUG(@"  bail -- existing is right size (%@)", NSStringFromCGSize(bounds.size));
                return; // Good to go!
            } else {
                PREVIEW_DEBUG(@"  existing is wrong size (%@ vs %@)", NSStringFromCGSize(bounds.size), NSStringFromCGSize(_preview.originalViewSize));
            }
        }
    } else {
        // Load it no matter what. The caller presumably knows that the on-disk data has changed.
    }
    
    PREVIEW_DEBUG(@"  starting op");
    
    // Load the preview in the background.
    _previewLoadOperation = [[OUIDocumentPreviewLoadOperation alloc] initWithProxy:self size:bounds.size];
    [_previewLoadOperation setQueuePriority:NSOperationQueuePriorityLow];
    [PreviewLoadOperationQueue addOperation:_previewLoadOperation];
}

- (void)cancelPreviewLoadIfRunning;
{
    OBPRECONDITION([NSThread isMainThread]);

    PREVIEW_DEBUG(@"%s", __PRETTY_FUNCTION__);

    [_previewLoadOperation cancel];
    [_previewLoadOperation release];
    _previewLoadOperation = nil;
}

- (id <OUIDocumentPreview>)currentPreview;
{
    return _preview;
}

- (void)discardPreview;
{
    // Right now this is only called during low memory when we aren't visible
    OBPRECONDITION(_view == nil);

    // really shouldn't have an operation if we aren't visible, but just in case
    OBASSERT(_previewLoadOperation == nil);
    [_previewLoadOperation cancel];
    [_previewLoadOperation autorelease];
    _previewLoadOperation = nil;

    [_preview release];
    _preview = nil;
}

- (void)previewDidLoad:(id <OUIDocumentPreview>)preview;
{
    OBPRECONDITION([NSThread isMainThread]); // Among other things, we poke the aspect ratio cache global
    
    [_previewLoadOperation autorelease];
    _previewLoadOperation = nil;
    
    BOOL isPlaceholder = NO;
    if (!preview || [preview isKindOfClass:[NSError class]]) {
        // This can be an error too. We need to get called to at least clear our pending operation and post a notification
        PREVIEW_DEBUG(@"%s error %@", __PRETTY_FUNCTION__, [(NSError *)preview toPropertyList]);
        isPlaceholder = YES;
        preview = [[[OUIDocumentImagePreview alloc] initWithImage:[OUIDocumentProxyView placeholderPreviewImage]] autorelease];
    }
        
    [_preview release];
    _preview = [preview retain];

    // Now that we have a preview, load the aspect ratio cache if necessary.
    {
        CGRect rect = _preview.untransformedPageRect;
        
        // Assumes that the PDF won't do a non X/Y uniform scale. We could make a 1x1 rect, get the transform for that rect and transform our page rect.
        CGFloat aspectRatio = CGRectGetWidth(rect)/CGRectGetHeight(rect);
        
        NSString *cacheKey = _aspectRatioCacheKey(self);
        
        NSDictionary *aspectRatioCache = [ProxyAspectRatioCachePreference dictionaryValue];
        if (aspectRatioCache == nil || [aspectRatioCache floatForKey:cacheKey defaultValue:-1] != aspectRatio) {
            NSMutableDictionary *updatedCache = [[NSMutableDictionary alloc] initWithDictionary:aspectRatioCache];
            
            if (isPlaceholder) {
                // Need to stop using any previous cached value now that we have no preview and just use the placeholder image size.
                [updatedCache removeObjectForKey:cacheKey];
            } else {
                // *Could* be valid outside this range, but probably not. Probably means a struct/float returning message was sent to nil somewhere.
                OBASSERT(aspectRatio > 1.0/20);
                OBASSERT(aspectRatio < 20.0);
                
                OBASSERT(!isinf(aspectRatio));
                [updatedCache setFloatValue:aspectRatio forKey:cacheKey];
            }
            
            [ProxyAspectRatioCachePreference setObjectValue:updatedCache];
            [updatedCache release];
            [[NSUserDefaults standardUserDefaults] autoSynchronize];
        }
    }
    
    if (_view) {
        PREVIEW_DEBUG(@"%s %p %@", __PRETTY_FUNCTION__, preview, isPlaceholder ? @"--" : NSStringFromCGSize(preview.originalViewSize));
        
        _view.preview = preview;
        
        [_view.superview setNeedsLayout];
        
        PREVIEW_DEBUG(@"  view %p, current size %@, _hasRetriedProxyDueToIncorrectSize %d", _view, NSStringFromCGSize(_view.frame.size), _hasRetriedProxyDueToIncorrectSize);
        // Our preview loading can fire off before we get told about the right device orientation. This is lame since we'll end up laying out previews twice, but at least it is async and not blurry. We only allow this hack to happen once per proxy, though, to avoid getting stuck looping.
        if (!_hasRetriedProxyDueToIncorrectSize) {
            _hasRetriedProxyDueToIncorrectSize = YES;
            //NSLog(@"retry!");
            [self startPreviewLoadIfNeeded:YES];
        }
    }
    
    [[NSNotificationCenter defaultCenter] postNotificationName:OUIDocumentProxyPreviewDidLoadNotification object:self];
}

#pragma mark -
#pragma mark Debugging

- (NSString *)shortDescription;
{
    return [NSString stringWithFormat:@"<%@:%p '%@' %@>", NSStringFromClass([self class]), self, self.name, _date];
}

#pragma mark -
#pragma mark Private

- (void)_documentProxyTapped:(UITapGestureRecognizer *)recognizer;
{
    if ([[OUIAppController controller] activityIndicatorVisible]) {
        OBASSERT_NOT_REACHED("Should have been blocked");
        return;
    }
    
    [_target performSelector:_action withObject:self];
}

@end
