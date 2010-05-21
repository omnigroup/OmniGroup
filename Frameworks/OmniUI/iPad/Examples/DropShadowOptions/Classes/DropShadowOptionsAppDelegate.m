//
//  DropShadowOptionsAppDelegate.m
//  DropShadowOptions
//
//  Created by Timothy J. Wood on 4/2/10.
//  Copyright The Omni Group 2010. All rights reserved.
//

#import "DropShadowOptionsAppDelegate.h"


#import "RootViewController.h"
#import "DetailViewController.h"


@implementation DropShadowOptionsAppDelegate

@synthesize window, splitViewController, rootViewController, detailViewController;


#pragma mark -
#pragma mark Application lifecycle

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {    
    
    // Override point for customization after app launch    
    
    // Add the split view controller's view to the window and display.
    [window addSubview:splitViewController.view];
    [window makeKeyAndVisible];
    
    return YES;
}


- (void)applicationWillTerminate:(UIApplication *)application {
    // Save data if appropriate
}


#pragma mark -
#pragma mark Memory management

- (void)dealloc {
    [splitViewController release];
    [window release];
    [super dealloc];
}


@end

