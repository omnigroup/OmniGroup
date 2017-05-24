// Copyright 2017 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.
//
//  OUIReceiptRefreshRequest.h
//  OmniUI
//
//  Created by reidc on 2/28/17.
//
// $Id$
 
#import <StoreKit/SKRequest.h>

///  This API provided here is intended to be used for sharing receipts across different apps. The cached receipt data function assumes a Group ID that is associated with a shared container. The receiptPath is the location within that group container at which the receipt data is stored. It is possible for the receipt data to be missing when it shouldn't, and logMessage is used to log that occurence for debugging. If there is no cached receipt found, your app may want to write a receipt to the cache. The ability to do this is gated behind canWriteReceiptToCache. The refreshRequestClass exists to allow custom handling of the request finishing. Passing in a custom OUIReceiptRefreshRequest subclass to this function ensures that your requestDidFinish logic is executed. You can pass in nil if you do not need to do any custom handling.
extern NSData *OUICachedReceiptData(NSString *groupID, NSString *receiptPath, NSString *logMessage, BOOL canWriteReceiptToCache, Class refreshRequestClass);

@interface OUIReceiptRefreshRequest : NSObject <SKRequestDelegate>

/// This method is exposed for subclass override. The overriding class should perform any necessary actions on return of the request. For example, after reading the refreshed receipt you may find that your app's license should change, and you handle that here.

/// IMPORTANT: Call super *after* handling the new reciept. OUIReceiptRefreshRequest's implementation releases the current OUIReceiptRefreshRequest (or subclass thereof). Calling OUICachedReceiptData in this method after calling super will fire off a new receipt refresh request.
- (void)requestDidFinish:(SKRequest *)request NS_REQUIRES_SUPER;


@end

