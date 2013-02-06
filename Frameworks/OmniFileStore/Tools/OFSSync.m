// Copyright 2008-2012 Omni Development, Inc. All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

RCS_ID("$Id$");

#import <OmniFileExchange/OFXServerAccount.h>
#import <OmniFileExchange/OFXServerAccountRegistry.h>
#import <OmniFileExchange/OFXServerAccountType.h>
#import <OmniFileExchange/OFXAgent.h>
#import <readpassphrase.h>

#import "OFSCommand.h"

/*
 Possible command tree
 
 server add type url [--name display-name]
 ... does a propfind, validates and stores the credentials
 server list
 ... lists all the servers with uuid, type, name, baseURL
 server remove name-or-uuid
 
 server config sync on|off
 ... if we want to be able to have servers that we only import/export but don't do the full sync
 
 file add [--server name-or-uuid] path-to-file
 ... adds the file to the sync container. uses the single server if there is only one or errors and requires a unique server be specified. possibly renames the files to avoid two files with the same name. returns the uuid.
 
 file list [--server name-or-uuid]
 ... lists the files in the sync container for the given server (or all servers) with uuids
 
 file remove uuid
 ... removes the file with the specified uuids
 
 file export name-or-uuid path-to-exported-file
 ... exports the given file from the server container to the output path
 
 sync [--server uuid]
 ... synchronizes the container for the specified servers (or all servers if none are given)
 
 conflict handling?
 
 help [other command]
 ... logs help
 
 Global flags
 
 -v
 Verbose mode
 
 */

static OFXServerAccountRegistry *accountRegistry(void)
{
    static OFXServerAccountRegistry *registry = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        registry = [OFXServerAccountRegistry defaultAccountRegistry];
    });
    
    return registry;
}

static OFXAgent *startAgent(void)
{
    // Only set this up on the first call (might be multiple if we get invoked with a 'source' command).
    static OFXAgent *agent = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSError *error = nil;
        agent = [[OFXAgent alloc] initWithApplicationIdentifier:@"com.omnigroup.OmniFileStore.OFSSync"
                                                remoteDirectoryName:nil
                                               containerIdentifiers:@[@"com.omnigroup.SomeApp"]
                                                              error:&error];
        if (!agent) {
            NSLog(@"Error creating sync agent: %@", [error toPropertyList]);
            exit(1);
        }
        
        [agent applicationLaunched];
    });
    return agent;
}

static void runAgent(OFXAgent *agent, NSTimeInterval duration)
{
    // It isn't clear what the final API is going to be here. Depends on what the most clear implementation of the sync agent is. By and large it should just get registered and should run on its own in response to various events. We shouldn't have to tell it to sync manually, but we might have a method to do force it to check the remote server (as if the app had just been activated or a timer had fired).
    NSTimeInterval startTime = [NSDate timeIntervalSinceReferenceDate];
    NSDate *endDate = [NSDate dateWithTimeIntervalSinceReferenceDate:startTime + duration];
    
    while ([endDate timeIntervalSinceNow] > 0) {
        [[NSRunLoop currentRunLoop] runUntilDate:endDate]; // Returns immediately if there are no timers/sources, but we want background operation queues to have time to run (and possibly register timers).
    }
        
    __block BOOL finished = NO;
    
    // Now that our minimum run time has finished, wait for any pending operations to finish
    [agent afterAsynchronousOperationsFinish:^{
        finished = YES;
    }];
    
    while (!finished) {
        @autoreleasepool {
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.5]];
        }
    }
}

int main(int argc, char *argv[])
{
    @autoreleasepool {
        OFSCommand *strongCommand = [OFSCommand command];
        __weak OFSCommand *cmd = strongCommand;
        
        // Register defaults
        [OBPostLoader processClasses];
        
        [cmd group:@"server" with:^{
            [cmd add:@"types # Lists the allowed types for newly created servers" with:^{
                for (OFXServerAccountType *type in [OFXServerAccountType accountTypes])
                    OFSCommandLog(@"%@\n", type.identifier);
            }];
            
            [cmd add:@"add type url --name # Adds a new sync server" with:^{
                NSString *typeName = cmd[@"type"];
                NSURL *baseURL = cmd[@"url"];
                NSString *name = cmd[@"name"];
                //NSString *uuid = cmd[@"uuid"];
                
                OFXServerAccountType *type = [OFXServerAccountType accountTypeWithIdentifier:typeName];
                if (!type)
                    [cmd error:@"No such account type \"%@\"", type];
                
                OFXServerAccount *account = [[OFXServerAccount alloc] initWithType:type];
                account.baseURL = baseURL;
                account.displayName = name;
                
                NSString *username, *password;
                {
                    const char *env;
                    
                    if ((env = getenv("OFSSyncUsername"))) {
                        username = [NSString stringWithUTF8String:env];
                    } else {
                        char buf[512];
                        fputs("Username: ", stdout);
                        if (!fgets(buf, sizeof(buf), stdin))
                            [cmd error:@"Failed to read username"];
                        
                        char *newline = strchr(buf, '\n');
                        if (newline)
                            *newline = '\0';
                        username = [NSString stringWithUTF8String:buf];
                    }

                    if ((env = getenv("OFSSyncPassword"))) {
                        password = [NSString stringWithUTF8String:env];
                    } else {
                        char buf[512];
                        if (!readpassphrase("Password: ", buf, sizeof(buf), 0/*options*/))
                            [cmd error:@"Failed to read password"];
                        password = [NSString stringWithUTF8String:buf];
                    }
                }

                __block BOOL finished = NO;
                
                [type validateAccount:account username:username password:password validationHandler:^(NSError *errorOrNil) {
                    if (errorOrNil)
                        [cmd error:@"%@", [errorOrNil localizedDescription]];
                    else
                        [accountRegistry() addAccount:account];
                    finished = YES;
                }];
                
                while (!finished) {
                    @autoreleasepool {
                        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
                    }
                }
            }];
            
            [cmd add:@"list # Lists the currently defined sync servers" with:^{
                for (OFXServerAccount *account in [accountRegistry() accounts]) {
                    OFSCommandLog(@"%@ %@ %@ %@\n", account.uuid, account.baseURL, account.displayName, account.credentialServiceIdentifier);
                }
            }];

            [cmd add:@"remove name-or-uuid # Removes an existing sync server" with:^{
                // The directory for the account isn't cleaned up here, but rather by OFXAgent (since we need to be sure it is done with it).
                NSString *nameOrUUID = cmd[@"name-or-uuid"];
                
                OFXServerAccount *account = [accountRegistry() accountWithUUID:nameOrUUID];
                if (!account)
                    account = [accountRegistry() accountWithDisplayName:nameOrUUID];
                if (!account)
                    [cmd error:@"No account with \"%@\" as a UUID or name.", nameOrUUID];
                
                [accountRegistry() removeAccount:account];
            }];
            
        }];

        [cmd add:@"run time # Starts a sync operation, waits for it to run or 'time' seconds, whichever is longer" with:^{
            OFXAgent *agent = startAgent();
            runAgent(agent, [cmd[@"time"] doubleValue]);
        }];

        [cmd add:@"reset # Removes the local and remote directories for all registered sync accounts and then forgets the accounts. This obviously will lose any data in those accounts" with:^{
            OFXAgent *agent = startAgent();

            [agent stopAndRemoveDataFromAllAccounts];
            
            // Now, forget all the accounts -- this will queue up another operation behind the one that stops and cleans the existing accounts.
            [accountRegistry() removeAllAccounts];

            runAgent(agent, 1);
        }];
        
        [cmd add:@"source file # Run commands from a file (ignoring whitespace and comment lines)" with:^{
            NSError *error = nil;
            NSURL *sourceFile = cmd[@"file"];
            NSLog(@"file = %@", sourceFile);
            NSString *sourceString = [[NSString alloc] initWithContentsOfURL:sourceFile encoding:NSUTF8StringEncoding error:&error];
            if (!sourceString)
                [cmd error:@"Unable to read source file %@: %@", [sourceFile absoluteString], [error localizedDescription]];
            
            [sourceString enumerateLinesUsingBlock:^(NSString *line, BOOL *stop){
                // TODO: No command line quoting done here.

                // Trim comments
                NSRange commentStartRange = [line rangeOfString:@"#"];
                if (commentStartRange.location != NSNotFound)
                    line = [line substringToIndex:commentStartRange.location];
                
                // Ignore empty lines
                line = [line stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                if ([NSString isEmptyString:line])
                    return;
                
                // TODO: Double-space will produce crazy results
                OFSCommandLog(@"## %@\n", line);
                [cmd runWithArguments:[line componentsSeparatedByString:@" "]];
            }];
        }];
        
        NSMutableArray *argumentStrings = [NSMutableArray array];
        for (int argi = 1; argi < argc; argi++)
            [argumentStrings addObject:[NSString stringWithUTF8String:argv[argi]]];
        [strongCommand runWithArguments:argumentStrings];
    }
    
    return 0;
}
