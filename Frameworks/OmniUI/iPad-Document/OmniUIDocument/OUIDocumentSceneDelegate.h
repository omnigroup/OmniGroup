// Copyright 2019 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <UIKit/UIResponder.h>

#import <UIKit/UIWindowScene.h> // For UIWindowSceneDelegate
#import <OmniUI/OUIUndoBarButtonItem.h> // For OUIUndoBarButtonItemTarget

NS_ASSUME_NONNULL_BEGIN

@class OUIDocument;

typedef NS_OPTIONS(NSUInteger, OUIDocumentPerformOpenURLOptions) {
    OUIDocumentPerformOpenURLOptionsImport = (1<<0),
    OUIDocumentPerformOpenURLOptionsOpenInPlaceAllowed = (1<<1),
    OUIDocumentPerformOpenURLOptionsRevealInBrowser = (1<<2),
};

@interface OUIDocumentSceneDelegate : UIResponder <UIWindowSceneDelegate, OUIUndoBarButtonItemTarget>

+ (nullable instancetype)documentSceneDelegateForView:(UIView *)view;
+ (NSArray <OUIDocumentSceneDelegate *> *)activeSceneDelegatesMatchingConditionBlock:(BOOL (^)(OUIDocumentSceneDelegate *sceneDelegate))conditionBlock;
+ (NSArray <OUIDocumentSceneDelegate *> *)documentSceneDelegatesForDocument:(OUIDocument *)document;

@property (nonatomic, nullable, readonly) UIWindowScene *windowScene;
@property (nonatomic, nullable, strong) UIWindow *window;
@property (nonatomic, nullable, strong) __kindof OUIDocument *document;
@property (nonatomic, readonly) UIDocumentBrowserViewController *documentBrowser;

@property (nonatomic, readonly) UIResponder *defaultFirstResponder;
@property (nonatomic, readonly) UIBarButtonItem *closeDocumentBarButtonItem;
@property (nonatomic, readonly) UIBarButtonItem *compactCloseDocumentBarButtonItem;
@property (nonatomic, readonly) UIBarButtonItem *infoBarButtonItem;
@property (nonatomic, readonly) UIBarButtonItem *uniqueInfoBarButtonItem;
@property (nonatomic, readonly) UIBarButtonItem *newAppMenuBarButtonItem;

- (IBAction)makeNewDocument:(nullable id)sender;
- (IBAction)closeDocument:(nullable id)sender;
- (void)closeDocumentWithCompletionHandler:(void(^ _Nullable)(void))completionHandler;

// Subclassing point for a portion of -scene:openURLContexts:.
- (void)performOpenURL:(NSURL *)url options:(OUIDocumentPerformOpenURLOptions)options;

- (void)documentWillRebuildViewController:(OUIDocument *)document;
- (void)documentDidRebuildViewController:(OUIDocument *)document;
- (void)documentDidFailToRebuildViewController:(OUIDocument *)document;

// UISceneDelegate method implemented by this class
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions;
- (void)sceneDidDisconnect:(UIScene *)scene;
- (nullable NSUserActivity *)stateRestorationActivityForScene:(UIScene *)scene;
- (void)scene:(UIScene *)scene openURLContexts:(NSSet<UIOpenURLContext *> *)URLContexts;

// Available for subclasses to override, in case it's not always a good time to process special URLs.
- (void)handleCachedSpecialURLIfNeeded;

@end

extern NSString * const OUIUserActivityUserInfoKeyBookmark;

NS_ASSUME_NONNULL_END
