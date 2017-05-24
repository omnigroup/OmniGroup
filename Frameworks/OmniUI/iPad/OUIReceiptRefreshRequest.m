// Copyright 2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
//  OUIReceiptRefreshRequest.m
//  OmniUI
//
//  Created by reidc on 2/28/17.
//
//
 
#import <OmniUI/OUIReceiptRefreshRequest.h>
#import <OmniFoundation/OFPreference.h>
#import <OmniFoundation/NSFileManager-OFSimpleExtensions.h>
#import <OmniBase/NSError-OBExtensions.h>
#import <StoreKit/SKReceiptRefreshRequest.h>

RCS_ID("$Id$");

static OUIReceiptRefreshRequest *_CurrentReceiptRefreshRequest = nil;
static NSError *_LastReceiptRefreshError = nil;

@implementation OUIReceiptRefreshRequest {
@private
    SKReceiptRefreshRequest *_refreshRequest;
}

+ (void)refreshReceipt;
{
    // Start a new request only if one isn't already in progress.
    // If we received an error from a previous request, don't attempt again on this launch of the application to avoid prompting the user repeatedly for their Apple ID credentials.
    
    if (_CurrentReceiptRefreshRequest == nil && _LastReceiptRefreshError == nil) {
        _CurrentReceiptRefreshRequest = [[self alloc] init];
    }
}

+ (void)finishedRefreshRequest:(OUIReceiptRefreshRequest *)request;
{
    OBRetainAutorelease(request);
    OBASSERT(request == _CurrentReceiptRefreshRequest);
    if (request == _CurrentReceiptRefreshRequest) {
        _CurrentReceiptRefreshRequest = nil;
    }
}

- (instancetype)init;
{
    self = [super init];
    if (self == nil) {
        return nil;
    }
    
    _refreshRequest = [[SKReceiptRefreshRequest alloc] initWithReceiptProperties:nil];
    if (_refreshRequest == nil) {
        return nil;
    }
    
    _refreshRequest.delegate = self;
    [_refreshRequest start];
    
    return self;
}

- (void)dealloc;
{
    _refreshRequest.delegate = nil;
}

- (void)requestDidFinish:(SKRequest *)request;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    [[self class] finishedRefreshRequest:self];
}

- (void)request:(SKRequest *)request didFailWithError:(NSError *)error;
{
    OBPRECONDITION([NSThread isMainThread]);
    
    _LastReceiptRefreshError = error;
    NSLog(@"Received error attempting to refresh receipt: %@", _LastReceiptRefreshError);
    
    [[self class] finishedRefreshRequest:self];
}

// The URL is where we cache the receipt. The refresh request class allows for apps that override requestDidFinish to get their custom handler code called when the receipt is refreshed.
static NSData *OUICopyReceiptToURLWithRefreshRequestClass(NSURL *cacheURL, Class refreshRequestClass)
{
    NSError *error = nil;
    NSURL *receiptURL = [[NSBundle mainBundle] appStoreReceiptURL];
    NSData *receiptData = [NSData dataWithContentsOfURL:receiptURL options:0 error:&error];
    if (receiptData == nil) {
        if ([error causedByMissingFile]) {
            // Request a new receipt, if allowed
            OFPreference *preference = [OFPreference preferenceForKey:@"AllowReceiptRefreshRequests"];
            BOOL allowReceiptRefresh = [preference boolValue];
            if (allowReceiptRefresh) {
                [refreshRequestClass refreshReceipt];
            }
        }
        return nil;
    }
    
    [receiptData writeToURL:cacheURL options:NSDataWritingAtomic error:NULL];
    return receiptData;
}

NSData *OUICachedReceiptData(NSString *groupID, NSString *relativeReceiptPath, NSString *failureLogMessage, BOOL shouldWriteReceiptToCache, Class refreshRequestClass)
{
    if (refreshRequestClass == nil) {
        refreshRequestClass = [OUIReceiptRefreshRequest class];
    }
    // The refreshRequestClass is intended to either be OUIReceiptRefreshRequest or a subclass thereof.
    OBASSERT([refreshRequestClass respondsToSelector:@selector(refreshReceipt)]);
    
    static NSURL *cachedReceiptURL;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSURL *containerURL = [[NSFileManager defaultManager] containerURLForBaseGroupContainerIdentifier:groupID];
        // Intentionally sharing the group container between iPhone and iPad/Universal apps so that someone who upgrades to Universal can get grandfathered iPhone features
        cachedReceiptURL = [containerURL URLByAppendingPathComponent:relativeReceiptPath];
    });
    
    // If we weren't able to find the container or receipt URL right away, don't ask NSData for its contents – it'll crash.
    if (cachedReceiptURL == nil) {
        static dispatch_once_t onceToken;
        dispatch_once(&onceToken, ^{
            NSLog(@"%@", failureLogMessage);
        });
        return nil;
    }
    
    NSError *error = nil;
    NSData *receiptData = [NSData dataWithContentsOfURL:cachedReceiptURL options:0 error:&error];
    if (receiptData == nil && shouldWriteReceiptToCache) {
        receiptData = OUICopyReceiptToURLWithRefreshRequestClass(cachedReceiptURL, refreshRequestClass); // Place this where the universal app can find it
    }
    
    return receiptData;
}

@end
