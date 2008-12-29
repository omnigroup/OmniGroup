// Copyright 1997-2005, 2007-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

#import <OmniFoundation/NSUserDefaults-OFExtensions.h>

#import <OmniFoundation/OFPreference.h>

RCS_ID("$Id$")

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
#import <OmniFoundation/OFScheduler.h>
#import <OmniFoundation/OFScheduledEvent.h>

//#define USE_NETINFO

#ifdef USE_NETINFO
#import <netinfo/ni.h>
#endif

@interface NSUserDefaults (OFPrivate)
- (void)_doSynchronize;
- (void)_scheduleSynchronizeEvent;

#ifdef USE_NETINFO
- (void)readNetInfo;
#endif
@end
#endif

@implementation NSUserDefaults (OFExtensions)

// OFBundleRegistryTarget informal protocol

+ (void)registerItemName:(NSString *)itemName bundle:(NSBundle *)bundle description:(NSDictionary *)description;
{
    if ([itemName isEqualToString:@"defaultsDictionary"]) {
        [[self standardUserDefaults] registerDefaults:description];
        [OFPreference recacheRegisteredKeys];
    }
}

- (void)autoSynchronize;
{
#if defined(TARGET_OS_IPHONE) && TARGET_OS_IPHONE
    [self synchronize];
#else
    // -_scheduleSynchronizeEvent pulls in OFScheduler and all that.  We might pull that in later anyway, but for now not so much.
    [self _scheduleSynchronizeEvent];
#endif
}

@end

#if !defined(TARGET_OS_IPHONE) || !TARGET_OS_IPHONE
@implementation NSUserDefaults (OFPrivate)

// TODO: Make pendingEventLock and pendingEvent instance-specific variables

static NSLock *_pendingEventLock = nil;
static OFScheduledEvent *_pendingEvent = nil;

+ (void)didLoad;
{
    _pendingEventLock = [[NSLock alloc] init];
}

- (void)_doSynchronize;
{
    [_pendingEventLock lock];
    [_pendingEvent release];
    _pendingEvent = nil;
    [_pendingEventLock unlock];
    [self synchronize];
}

- (void)_scheduleSynchronizeEvent;
{
    [_pendingEventLock lock];
    if (_pendingEvent == nil)
        _pendingEvent = [[[OFScheduler mainScheduler] scheduleSelector:@selector(_doSynchronize) onObject:self afterTime:60.0] retain];
    [_pendingEventLock unlock];
}

//

#ifdef USE_NETINFO
static BOOL OFUserDefaultsDebugNetInfo = NO;

// This could read NIS+ on Solaris, if we care that much someday

- (void)readNetInfo;
{
    NSString *preferencesDirectoryName;
    void *handle;
    
    OBPRECONDITION(ownerName != nil);

    if (overrideNetworkDictionary)
	return; // Already read

    overrideNetworkDictionary = [[NSMutableDictionary alloc] init];
    advisoryNetworkDictionary = [[NSMutableDictionary alloc] init];
    preferencesDirectoryName = [NSString stringWithFormat:@"/application_preferences/%@", ownerName];

    if (ni_open(NULL, ".", &handle) != NI_OK)
	return;

    while (1) {
	ni_id defaultsDirectory;
	ni_proplist propertyList;
	unsigned int propertyIndex;
	void *oldHandle;
	ni_status status;

	if (ni_root(handle, &defaultsDirectory) != NI_OK)
	    goto loopToHigherDomain;

	if (ni_pathsearch(handle, &defaultsDirectory, [preferencesDirectoryName cString]) != NI_OK)
	    goto loopToHigherDomain;

	changeCount++;

	ni_read(handle, &defaultsDirectory, &propertyList);

	for (propertyIndex = 0; propertyIndex < propertyList.ni_proplist_len; propertyIndex++) {
	    ni_property property;
	    ni_namelist namelist;
	    
	    property = propertyList.ni_proplist_val[propertyIndex];

	    if (strcmp(property.nip_name, "name") != 0) {
		namelist = property.nip_val;
                switch (namelist.ni_namelist_len) {
                    default:
                        break;
                    case 2:
                        if (strcmp("override", namelist.ni_namelist_val[1]) == 0) {
                            if (OFUserDefaultsDebugNetInfo)
                                NSLog(@"Read protected '%s' = '%s'", property.nip_name, namelist.ni_namelist_val[0]);
                            [overrideNetworkDictionary setObject:[NSString stringWithCString:namelist.ni_namelist_val[0]] forKey:[NSString stringWithCString:property.nip_name]];
                            break;
                        }
                    case 1:
                        if (OFUserDefaultsDebugNetInfo)
                            NSLog(@"Read property '%s' = '%s'", property.nip_name, namelist.ni_namelist_val[0]);
                        [advisoryNetworkDictionary setObject:[NSString stringWithCString:namelist.ni_namelist_val[0]] forKey:[NSString stringWithCString:property.nip_name]];
                        break;
                }
	    }
	}
	ni_proplist_free(&propertyList);

loopToHigherDomain:
	oldHandle = handle;
        status = ni_open(oldHandle, "..", &handle);
	ni_free(oldHandle);
	if (status != NI_OK)
	    return;
    }
}
#endif

@end
#endif
