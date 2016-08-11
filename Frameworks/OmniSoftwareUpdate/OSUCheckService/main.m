// Copyright 2015-2016 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <Foundation/Foundation.h>

#import "OSUCheckService.h"
#import "OSULookupCredentialProtocol.h"

RCS_ID("$Id$");

@interface ServiceDelegate : NSObject <NSXPCListenerDelegate>
@end

@implementation ServiceDelegate

- (BOOL)listener:(NSXPCListener *)listener shouldAcceptNewConnection:(NSXPCConnection *)newConnection;
{
    NSXPCInterface *interface = [NSXPCInterface interfaceWithProtocol:@protocol(OSUCheckService)];
    
    // Sets the allowed values for collections that are in this argument. XPC doesn't allow use to specify the allowed values for a property inside our OSURunOperationParameters class, which is why this is split out into its own argument.
    [interface setClasses:[NSSet setWithObjects:[NSDictionary class], [NSString class], nil] forSelector:@selector(performCheck:runtimeStats:probes:lookupCredential:withReply:) argumentIndex:1 ofReply:NO];
    [interface setClasses:[NSSet setWithObjects:[NSDictionary class], [NSString class], nil] forSelector:@selector(performCheck:runtimeStats:probes:lookupCredential:withReply:) argumentIndex:2 ofReply:NO];
    
    [interface setInterface:[NSXPCInterface interfaceWithProtocol:@protocol(OSULookupCredential)] forSelector:@selector(performCheck:runtimeStats:probes:lookupCredential:withReply:) argumentIndex:3 ofReply:NO];
    
    newConnection.exportedInterface = interface;
    
    OSUCheckService *exportedObject = [OSUCheckService new];
    newConnection.exportedObject = exportedObject;
    
    [newConnection resume];
    
    return YES;
}

@end

int main(int argc, const char *argv[])
{
    // Create the delegate for the service.
    ServiceDelegate *delegate = [ServiceDelegate new];
    
    // Set up the one NSXPCListener for this service. It will handle all incoming connections.
    NSXPCListener *listener = [NSXPCListener serviceListener];
    listener.delegate = delegate;
    
    // Resuming the serviceListener starts this service. This method does not return.
    [listener resume];
    return 0;
}
