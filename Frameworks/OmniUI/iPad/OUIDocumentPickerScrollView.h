// Copyright 2010-2011 The Omni Group. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
// $Id$

#import <UIKit/UIView.h>

extern NSString * const OUIDocumentPickerScrollViewProxiesBinding;

@class OFPreference;
@class OUIDocumentProxy, OUIDocumentPickerScrollView;
@class OUIDocumentSlider;

typedef struct {
    NSTimer *timer;
    CGFloat x0;
    CGFloat v0;
    CGFloat a;
    CFTimeInterval t0;
    BOOL bouncing;
} OUIDocumentPickerScrollViewSmoothScroll;

typedef enum {
    OUIDocumentProxySortByDate,
    OUIDocumentProxySortByName,
} OUIDocumentProxySort;

@protocol OUIDocumentPickerScrollViewDelegate <UIScrollViewDelegate>
- (void)documentPickerView:(OUIDocumentPickerScrollView *)pickerView didSelectProxy:(OUIDocumentProxy *)proxy;
@end

@interface OUIDocumentPickerScrollView : UIScrollView
{
@private
    BOOL _disableLayout;
    CGFloat _bottomGap;
    NSMutableSet *_proxies;
    NSArray *_sortedProxies;

    NSArray *_proxyViews;
    
    CGPoint _contentOffsetOnPanStart;

    OUIDocumentPickerScrollViewSmoothScroll _smoothScroll;
    struct {
        unsigned int needsRecentering:1;
        unsigned int isRotating:1;
    } _flags;
    
    BOOL _disableScroll;     // we are turning off UIScrollView scrolling already, needed a different flag
    BOOL _disableRotationDisplay;

    IBOutlet OUIDocumentSlider *_documentSlider;
    
    OUIDocumentProxySort _proxySort;
}

@property(nonatomic,assign) id <OUIDocumentPickerScrollViewDelegate> delegate;

@property(nonatomic,assign) BOOL disableLayout;
@property(nonatomic,assign) CGFloat bottomGap;
@property(nonatomic,retain) NSSet *proxies;
@property(nonatomic,readonly) NSArray *sortedProxies;

@property(readonly,nonatomic) OUIDocumentProxy *firstProxy;
@property(readonly,nonatomic) OUIDocumentProxy *lastProxy;
@property(readonly,nonatomic) OUIDocumentProxy *proxyClosestToCenter;
- (OUIDocumentProxy *)proxyToLeftOfProxy:(OUIDocumentProxy *)proxy;
- (OUIDocumentProxy *)proxyToRightOfProxy:(OUIDocumentProxy *)proxy;

- (void)snapToProxy:(OUIDocumentProxy *)proxy animated:(BOOL)animated;
- (void)sortProxies;

@property(readonly,nonatomic) OUIDocumentProxy *selectedProxy;

- (void)willRotate;
- (void)didRotate;

@property(assign) BOOL disableScroll;
@property(assign) BOOL disableRotationDisplay;

- (IBAction)documentSliderAction:(OUIDocumentSlider *)slider;

@property(nonatomic) OUIDocumentProxySort proxySort;
@end
