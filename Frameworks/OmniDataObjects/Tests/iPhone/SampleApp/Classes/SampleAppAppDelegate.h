//
//  SampleAppAppDelegate.h
//  SampleApp
//
//  Created by Timothy J. Wood on 10/4/08.
//  Copyright The Omni Group 2008. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface SampleAppAppDelegate : NSObject <UIApplicationDelegate> {
    
    UIWindow *window;
    UINavigationController *navigationController;
}

@property (nonatomic, retain) IBOutlet UIWindow *window;
@property (nonatomic, retain) IBOutlet UINavigationController *navigationController;

@end

