// Copyright 2002-2008 Omni Development, Inc.  All rights reserved.
//
// This software may only be used and reproduced according to the
// terms in the file OmniSourceLicense.html, which should be
// distributed with this project and can also be found at
// <http://www.omnigroup.com/developer/sourcecode/sourcelicense/>.

RCS_ID("$Id$");

#import "OSUCheckTool.h"
#import "OSURunTime.h"

#import <IOKit/IOCFBundle.h>
#import <IOKit/graphics/IOGraphicsLib.h>
#import <OpenGL/OpenGL.h>
#import <OpenGL/gl.h>
#import <QuickTime/QuickTime.h>
#import <inttypes.h>
#import <mach-o/arch.h>
#import <mach/mach_error.h>
#import <sys/sysctl.h>

// CFCopyDescription on a CFDataRef yields "<CFData 0x67d10 [0xa01303fc]>{length = 4, capacity = 4, bytes = 0x00001002}" when we'd like "0x00001002"
static CFStringRef data_desc(CFDataRef data)
{
    unsigned int byteIndex, byteCount = CFDataGetLength(data);
    if (byteCount == 0)
        return CFSTR("0x0");
    const UInt8 *bytes = CFDataGetBytePtr(data);
    
    CFMutableStringRef str = CFStringCreateMutableCopy(kCFAllocatorDefault, 2 + 2*byteCount, CFSTR("0x"));
    for (byteIndex = 0; byteIndex < byteCount; byteIndex++)
        CFStringAppendFormat(str, NULL, CFSTR("%02x"), bytes[byteIndex]);
    return str;
}

static void setUInt32Key(CFMutableDictionaryRef dict, CFStringRef key, uint32_t value)
{
    CFStringRef valueString = CFStringCreateWithFormat(kCFAllocatorDefault, NULL, CFSTR("%" PRIu32), value);
    CFDictionarySetValue(dict, key, valueString);
    CFRelease(valueString);
}

static void setUInt64Key(CFMutableDictionaryRef dict, CFStringRef key, uint64_t value)
{
    CFStringRef valueString = CFStringCreateWithFormat(kCFAllocatorDefault, NULL, CFSTR("%" PRIu64), value);
    CFDictionarySetValue(dict, key, valueString);
    CFRelease(valueString);
}

/*
 static void setCStringKey(CFMutableDictionaryRef dict, CFStringRef key, const char *value)
 {
 CFStringRef valueString = CFStringCreateWithCString(kCFAllocatorDefault, value, kCFStringEncodingUTF8);
 CFDictionarySetValue(dict, key, valueString);
 CFRelease(valueString);
 }
 */

static void setSysctlIntKey(CFMutableDictionaryRef dict, CFStringRef key, int name[], int nameCount)
{
    union {
        uint32_t ui32;
        uint64_t ui64;
    } value;
    value.ui64 = (uint64_t)-1;
    
    size_t valueSize = sizeof(value);
    if (sysctl(name, nameCount, &value, &valueSize, NULL, 0) < 0) {
        perror("sysctl");
        value.ui32 = (uint32_t)-1;
        valueSize  = sizeof(value.ui32);
    }
    
    // Might get back a 64-bit value for size/cycle values
    if (valueSize == sizeof(value.ui32))
        setUInt32Key(dict, key, value.ui32);
    else if (valueSize == sizeof(value.ui64))
        setUInt64Key(dict, key, value.ui64);
}

static void setSysctlStringKey(CFMutableDictionaryRef dict, CFStringRef key, int name[], int nameCount)
{
    size_t bufSize = 0;
    
    // Passing a null pointer just says we want to get the size out
    if (sysctl(name, nameCount, NULL, &bufSize, NULL, 0) < 0) {
	perror("sysctl");
	return;
    }
    
    char *value = calloc(1, bufSize + 1);
    
    if (sysctl(name, nameCount, value, &bufSize, NULL, 0) < 0) {
	// Not expecting any errors now!
	free(value);
	perror("sysctl");
	return;
    }
    
    CFStringRef str = CFStringCreateWithCString(kCFAllocatorDefault, value, kCFStringEncodingUTF8);
    CFDictionarySetValue(dict, key, str);
    CFRelease(str);
    free(value);
}

static NSDictionary *copySystemProfileForDataType(NSString *dataType)
{
    NSPipe *pipe = [NSPipe pipe];
    NSTask *task = [[[NSTask alloc] init] autorelease];
    [task setLaunchPath:@"/usr/sbin/system_profiler"];
    [task setArguments:[NSArray arrayWithObjects:@"-xml", dataType, @"-detailLevel", @"mini", nil]];
    [task setStandardOutput:pipe];
    [task launch];
    
    NSFileHandle *outputHandle = [pipe fileHandleForReading];
    NSData *output = [outputHandle readDataToEndOfFile];
    
    NSString *errorString = nil;
    id plist = [NSPropertyListSerialization propertyListFromData:output mutabilityOption:NSPropertyListImmutable format:NULL errorDescription:&errorString];
    if (!plist && errorString) {
#ifdef DEBUG    
	NSLog(@"Unable to query system profile for '%@' -- '%@'", dataType, errorString);
#endif	
    }
    
    if (![plist isKindOfClass:[NSArray class]]) {
#ifdef DEBUG    
	NSLog(@"Unable to query system profile for '%@' -- Expected array, but got %@", dataType, NSStringFromClass([plist class]));
#endif	
	return nil;
    }
    if ([plist count] == 0) {
#ifdef DEBUG    
	NSLog(@"Unable to query system profile for '%@' -- Got empty array at top level", dataType);
#endif	
	return nil;
    }
    
    plist = [plist objectAtIndex:0];
    if (![plist isKindOfClass:[NSDictionary class]]) {
#ifdef DEBUG    
	NSLog(@"Unable to query system profile for '%@' -- Expected dictionary, but got %@", dataType, NSStringFromClass([plist class]));
#endif	
	return nil;
    }
    
    plist = [plist objectForKey:@"_items"];
    if (!plist) {
#ifdef DEBUG
	NSLog(@"Unable to query system profile for '%@' -- No '_items' key in dictionary", dataType);
#endif	
	return nil;
    }
    if (![plist isKindOfClass:[NSArray class]]) {
#ifdef DEBUG    
	NSLog(@"Unable to query system profile for '%@' -- '_items' should have been an array, but was a %@", dataType, NSStringFromClass([plist class]));
#endif	
	return nil;
    }
    if ([plist count] == 0) {
#ifdef DEBUG    
	NSLog(@"Unable to query system profile for '%@' -- '_items' was empty", dataType);
#endif	
	return nil;
    }
    plist = [plist objectAtIndex:0];
    if (![plist isKindOfClass:[NSDictionary class]]) {
#ifdef DEBUG    
	NSLog(@"Unable to query system profile for '%@' -- '_items' element should have been an array, but was a %@", dataType, NSStringFromClass([plist class]));
#endif	
	return nil;
    }
    
    [plist retain];
    
    return plist;
}

CFDictionaryRef OSUCheckToolCollectHardwareInfo(const char *applicationIdentifier, bool collectHardwareInformation, const char *licenseType, bool reportMode)
{
    CFMutableDictionaryRef info = CFDictionaryCreateMutable(kCFAllocatorDefault, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
    
    // Run time stats from OSURunTime.
    CFStringRef appapplicationIdentifierString = CFStringCreateWithCString(kCFAllocatorDefault, applicationIdentifier, kCFStringEncodingUTF8);
    OSURunTimeAddStatisticsToInfo((NSString *)appapplicationIdentifierString, (NSMutableDictionary *)info);
    CFRelease(appapplicationIdentifierString);
    
    if (!collectHardwareInformation)
        // The user has opted out.  We still send along the application name and bundle version.  We may use it someday to filter the result that is returned to just the pertinent info for that app.
    return info;
    
    // License type (bundle, retail, demo, etc)
    {
        CFStringRef value = CFStringCreateWithCString(kCFAllocatorDefault, licenseType, kCFStringEncodingUTF8);
        CFDictionarySetValue(info, CFSTR("license-type"), value);
        CFRelease(value);
    }
    
    // UUID for the user's machine
    {
        CFStringRef domain = CFSTR("com.omnigroup.OmniSoftwareUpdate");
        CFStringRef key    = CFSTR("uuid");
        
        CFStringRef uuidString = CFPreferencesCopyAppValue(key, domain);
        if (!uuidString) {
            CFUUIDRef uuid = CFUUIDCreate(kCFAllocatorDefault);
            if (uuid) {
                uuidString = CFUUIDCreateString(kCFAllocatorDefault, uuid);
                CFRelease(uuid);
                CFPreferencesSetAppValue(key, uuidString, domain);
                CFPreferencesAppSynchronize(domain);
            }
        }
        CFDictionarySetValue(info, key, uuidString);
        CFRelease(uuidString);
    }
    
    // OS Version
    {
        // sysctlbyname("kern.osrevision"...) returns an error, Radar #3624904
        //setSysctlStringKey(info, "kern.osrevision");
        
        SInt32 major, minor, bug;
        Gestalt(gestaltSystemVersionMajor, &major);
        Gestalt(gestaltSystemVersionMinor, &minor);
        Gestalt(gestaltSystemVersionBugFix, &bug);

        CFStringRef userVisibleSystemVersion = CFStringCreateWithFormat(kCFAllocatorDefault, NULL, CFSTR("%d.%d.%d"), major, minor, bug);
        
        CFDictionarySetValue(info, CFSTR("os"), userVisibleSystemVersion);
        CFRelease(userVisibleSystemVersion);
    }
    
    // User's language
    {
        CFArrayRef languages = CFPreferencesCopyAppValue(CFSTR("AppleLanguages"), CFSTR("NSGlobalDomain"));
        if (languages) {
            if (CFGetTypeID(languages) == CFArrayGetTypeID() && CFArrayGetCount(languages) > 0) {
                // Only log their most prefered language
                CFStringRef language = CFArrayGetValueAtIndex(languages, 0);
                CFDictionarySetValue(info, CFSTR("lang"), language);
            }
            CFRelease(languages);
        }
    }
    
    // Location reported via the System Preferences TimeZone pane (or possibly via a GPS dongle; that seems less likely, though)
    {
	MachineLocation location;
	memset(&location, 0, sizeof(location));
	ReadLocation(&location);
        
        // This wasn't present under 10.2
#ifndef FractToFloat
#define FractToFloat(a)     ((float)(a) / fract1)
#endif
        
	// These are reported with a scale of 1/90.  Convert them to the normal representation.
	CFStringRef value = CFStringCreateWithFormat(kCFAllocatorDefault, NULL, CFSTR("%f,%f"), 90*FractToFloat(location.latitude), 90*FractToFloat(location.longitude));
	CFDictionarySetValue(info, CFSTR("loc"), value);
	CFRelease(value);
    }
    
    // Computer model
    {
        int name[] = {CTL_HW, HW_MODEL};
        setSysctlStringKey(info, CFSTR("hw-model"), name, 2);
    }
    
    // Number of processors
    {
        int name[] = {CTL_HW, HW_NCPU};
        setSysctlIntKey(info, CFSTR("ncpu"), name, 2);
    }
    
    // Type/Subtype of processors
    {
        // sysctl -a reports 'hw.cputype'/'hw.cpusubtype', but there are no defines for the names.
        const NXArchInfo *archInfo = NXGetLocalArchInfo();
        if (archInfo) {
            CFStringRef value = CFStringCreateWithFormat(kCFAllocatorDefault, NULL, CFSTR("%d,%d"), archInfo->cputype, archInfo->cpusubtype);
            CFDictionarySetValue(info, CFSTR("cpu"), value);
            CFRelease(value);
            
            // Radar #3624895: This will report 'ppc' instead of 'ppc970' when DYLD_IMAGE_SUFFIX=_debug
            // No real reason to report this if we send the type/subtype
            //setCStringKey(info, CFSTR("hw_name"), archInfo->name);
        }
    }
    
    // CPU Hz
    {
        int name[] = {CTL_HW, HW_CPU_FREQ};
        setSysctlIntKey(info, CFSTR("cpuhz"), name, 2);
    }
    
    // Bus Hz
    {
        int name[] = {CTL_HW, HW_BUS_FREQ};
        setSysctlIntKey(info, CFSTR("bushz"), name, 2);
    }
    
    // MB of memory
    {
        // The HW_PHYSMEM key has been replaced by HW_MEMSIZE for 64-bit values.  This isn't in the 10.2.8 headers I have, but it works on 10.2.8
#ifndef HW_MEMSIZE
#define HW_MEMSIZE      24              /* uint64_t: physical ram size */
#endif
        int name[] = {CTL_HW, HW_MEMSIZE};
        setSysctlIntKey(info, CFSTR("mem"), name, 2);
    }
    
    // Displays and accelerators
    {
        kern_return_t krc;
        
        mach_port_t masterPort;
        krc = IOMasterPort(bootstrap_port, &masterPort);
        if (krc != KERN_SUCCESS) {
            fprintf(stderr, "IOMasterPort returned 0x%08x -- %s\n", krc, mach_error_string(krc));
            goto iokit_error;
        }
        
        {
            CFMutableDictionaryRef pattern = IOServiceMatching(kIOAcceleratorClassName);
            //CFShow(pattern);
            
            io_iterator_t deviceIterator;
            krc = IOServiceGetMatchingServices(masterPort, pattern, &deviceIterator);
            if (krc != KERN_SUCCESS) {
                fprintf(stderr, "IOServiceGetMatchingServices returned 0x%08x -- %s\n", krc, mach_error_string(krc));
                goto accelerator_enum_error;
            }
            
            unsigned int acceleratorIndex = 0;
            io_object_t object;
            while ((object = IOIteratorNext(deviceIterator))) {
                CFMutableDictionaryRef properties = NULL;
                krc = IORegistryEntryCreateCFProperties(object, &properties, kCFAllocatorDefault, (IOOptionBits)0);
                if (krc != KERN_SUCCESS) {
                    fprintf(stderr, "IORegistryEntryCreateCFProperties returned 0x%08x -- %s\n", krc, mach_error_string(krc));
                    goto accelerator_object_error;
                }
                //CFShow(properties);
                
                
                CFStringRef glBundle = CFDictionaryGetValue(properties, CFSTR("IOGLBundleName"));
                CFStringRef version  = CFDictionaryGetValue(properties, CFSTR("IOSourceVersion"));
                CFStringRef bundleID = CFDictionaryGetValue(properties, kIOBundleIdentifierKey);
                
                if (glBundle) {
                    CFStringRef key = CFStringCreateWithFormat(kCFAllocatorDefault, NULL, CFSTR("accel%d_gl"), acceleratorIndex);
                    CFDictionarySetValue(info, key, glBundle);
                    CFRelease(key);
                }
                if (version) {
                    CFStringRef key = CFStringCreateWithFormat(kCFAllocatorDefault, NULL, CFSTR("accel%d_ver"), acceleratorIndex);
                    CFDictionarySetValue(info, key, version);
                    CFRelease(key);
                }
                if (bundleID) {
                    CFStringRef key = CFStringCreateWithFormat(kCFAllocatorDefault, NULL, CFSTR("accel%d_id"), acceleratorIndex);
                    CFDictionarySetValue(info, key, bundleID);
                    CFRelease(key);
                }
                
                // Look up the parent tree the 'device-id' and 'vendor-id' keys that are build by IOPCIBridge from the vendor/device info in the kIOPCIConfigVendorID if the PCI config space.
                // See <http://www.pcidatabase.com> for a nice free database of vendor/device pairs.
                CFDataRef vendor = IORegistryEntrySearchCFProperty(object, kIOServicePlane,
                                                                   CFSTR("vendor-id"),
                                                                   kCFAllocatorDefault,
                                                                   kIORegistryIterateRecursively|kIORegistryIterateParents);
                CFDataRef device = IORegistryEntrySearchCFProperty(object, kIOServicePlane,
                                                                   CFSTR("device-id"),
                                                                   kCFAllocatorDefault,
                                                                   kIORegistryIterateRecursively|kIORegistryIterateParents);
                if (vendor && device) {
                    CFStringRef vendorString = data_desc(vendor);
                    CFStringRef deviceString = data_desc(device);
                    
                    CFStringRef key   = CFStringCreateWithFormat(kCFAllocatorDefault, NULL, CFSTR("accel%d_pci"), acceleratorIndex);
                    CFStringRef value = CFStringCreateWithFormat(kCFAllocatorDefault, NULL, CFSTR("%@,%@"), vendorString, deviceString);
                    CFRelease(vendorString);
                    CFRelease(deviceString);
                    
                    CFDictionarySetValue(info, key, value);
                    CFRelease(key);
                    CFRelease(value);
                }
                
                
                // We can't get the device memory from IOKit since all IOKit knows are the PCI address ranges (in the IODeviceMemory key for the accelerator's IOPCIDevice owner).  This may be bigger than the actual amount of memory on the hardware (since one card may support different amounts of memory and its easiest for the PCI glue to report the max).
                // Instead we'll get the info from the CGLRenderer API below (since we have no good way of associating IOKit devices with CGL renderers).
                
                acceleratorIndex++;
                
            accelerator_object_error:
                if (properties)
                    CFRelease(properties);
                IOObjectRelease(object);
            }
            
            IOObjectRelease(deviceIterator);
        }
    accelerator_enum_error:
    iokit_error:
        
        
        // CGL video memory size for all accelerated renders.  As noted above, we don't have a good way of associating this with the actual hardware above, but really what we mostly care about is the actual sizes across the cards, not which card has how much.
        // The display mask given to CGLQueryRendererInfo means "make sure the renderer applies to ALL these displays".  We'll only worry about up to four displays.
        {
            unsigned int displayIndex;
            CFMutableStringRef rendererMem = CFStringCreateMutable(kCFAllocatorDefault, 0);
            
            for (displayIndex = 0; displayIndex < 4; displayIndex++) {
                CGLError err;
                CGLRendererInfoObj rendererInfo;
                GLint rendererIndex, rendererCount;
                
                // Don't bail on a kCGLBadDisplay here.  This can happen if you have a PCI video card plugged in but w/o a monitor attached.  We'll only look at a limited number of displays due to the enclosing 'for' loop anyway.
                
                err = CGLQueryRendererInfo((1<<displayIndex) /* display mask */, &rendererInfo, &rendererCount);
                if (err == kCGLBadDisplay)
                    continue;
                if (err) {
                    fprintf(stderr, "CGLQueryRendererInfo -> %d %s\n", err, CGLErrorString(err));
                    rendererCount = 0;
                }
                
                for (rendererIndex = 0; rendererIndex < rendererCount; rendererIndex++) {
                    GLint accelerated;
                    
                    err = CGLDescribeRenderer(rendererInfo, rendererIndex, kCGLRPAccelerated, &accelerated);
                    if (err) {
                        fprintf(stderr, "CGLQueryRendererInfo(%ld, kCGLRPAccelerated) -> %d\n", (long)rendererIndex, err);
                        continue;
                    }
                    if (!accelerated) {
                        // Software renderer; skip
                        continue;
                    }
                    
                    GLint videoMemory;
                    err = CGLDescribeRenderer(rendererInfo, rendererIndex, kCGLRPVideoMemory, &videoMemory);
                    if (err) {
                        fprintf(stderr, "CGLQueryRendererInfo(%ld, kCGLRPVideoMemory) -> %d\n", (long)rendererIndex, err);
                        continue;
                    }
                    
                    if (CFStringGetLength(rendererMem))
                        CFStringAppend(rendererMem, CFSTR(","));
                    CFStringAppendFormat(rendererMem, NULL, CFSTR("%ld"), videoMemory);
                }
            }
            
            CFDictionarySetValue(info, CFSTR("accel_mem"), rendererMem);
            CFRelease(rendererMem);
        }
        
        // Display mode and QuartzExtreme boolean for up to 4 displays
        {
            CGDirectDisplayID displays[4];
            CGDisplayCount displayIndex, displayCount;
            
            CGDisplayErr err = CGGetActiveDisplayList(4, displays, &displayCount);
            if (err == CGDisplayNoErr) {
                for (displayIndex = 0; displayIndex < displayCount; displayIndex++) {
                    CFNumberRef width, height, refreshRate;
                    CFStringRef pixelEncoding;
#if defined(MAC_OS_X_VERSION_10_6) && (MAC_OS_X_VERSION_MIN_REQUIRED >= MAC_OS_X_VERSION_10_6)
                    CGDisplayModeRef mode = CGDisplayCopyDisplayMode(displays[displayIndex]);
                    if (!mode)
                        continue;
                    int32_t size;
                    
                    size = CGDisplayModeGetWidth(mode);
                    width = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &size);
                    
                    size = CGDisplayModeGetHeight(mode);
                    height = CFNumberCreate(kCFAllocatorDefault, kCFNumberSInt32Type, &size);
                    
                    double refreshRateDouble = CGDisplayModeGetRefreshRate(mode);
                    refreshRate = CFNumberCreate(kCFAllocatorDefault, kCFNumberDoubleType, &refreshRateDouble);
                    
                    pixelEncoding = CGDisplayModeCopyPixelEncoding(mode);
#else
                    CFDictionaryRef mode = CGDisplayCurrentMode(displays[displayIndex]);
                    if (!mode)
                        continue;
                    width = CFDictionaryGetValue(mode, kCGDisplayWidth);
                    height = CFDictionaryGetValue(mode, kCGDisplayHeight);
                    refreshRate = CFDictionaryGetValue(mode, kCGDisplayRefreshRate);
                    pixelEncoding = CFStringCreateWithFormat(kCFAllocatorDefault, NULL, CFSTR("%@"), CFDictionaryGetValue(mode, kCGDisplayBitsPerPixel));
#endif
                    CFStringRef key = CFStringCreateWithFormat(kCFAllocatorDefault, NULL, CFSTR("display%d"), displayIndex);
                    CFStringRef format = reportMode ? CFSTR("%@x%@, %@ bits, %@Hz") : CFSTR("%@,%@,%@,%@");
                    CFStringRef value = CFStringCreateWithFormat(kCFAllocatorDefault, NULL, format, width, height, pixelEncoding, refreshRate);
                    CFDictionarySetValue(info, key, value);
		    
		    {
                        CFStringRef key = CFStringCreateWithFormat(kCFAllocatorDefault, NULL, CFSTR("qe%d"), displayIndex);
			CFStringRef value = CGDisplayUsesOpenGLAcceleration(displays[displayIndex]) ? CFSTR("1") : CFSTR("0");
			CFDictionarySetValue(info, key, value);
		    }
                }
            }
        }
    }
    
    // OpenGL extensions for the main display adaptor.
    do {
	NSOpenGLPixelFormatAttribute attributes[] = {
	    NSOpenGLPFAFullScreen,
	    NSOpenGLPFAScreenMask,
	    CGDisplayIDToOpenGLDisplayMask(CGMainDisplayID()),
	    NSOpenGLPFAAccelerated,
	    NSOpenGLPFANoRecovery,
	    0
	};
	
	NSString *vendor     = @"";
	NSString *version    = @"";
	NSString *renderer   = @"";
	NSString *extensions = @"";
	NSOpenGLPixelFormat *pixelFormat = [[NSOpenGLPixelFormat alloc] initWithAttributes:attributes];
	if (!pixelFormat) {
#ifdef DEBUG
	    NSLog(@"Unable to create pixel format");
#endif
	} else {
	    NSOpenGLContext *context = [[NSOpenGLContext alloc] initWithFormat:pixelFormat shareContext:nil];
	    if (!context) {
#ifdef DEBUG
		NSLog(@"Unable to create gl context");
#endif
	    } else {
		[context makeCurrentContext];
		if ([NSOpenGLContext currentContext] != context) {
#ifdef DEBUG
		    NSLog(@"Unable to make gl context current");
#endif
		} else {
		    const GLubyte *glStr;
		    
		    if ((glStr = glGetString(GL_VENDOR)))
			vendor = [[NSString alloc] initWithCString:(const char *)glStr];
		    if ((glStr = glGetString(GL_VERSION)))
			version = [[NSString alloc] initWithCString:(const char *)glStr];
		    if ((glStr = glGetString(GL_RENDERER)))
			renderer = [[NSString alloc] initWithCString:(const char *)glStr];
		    if ((glStr = glGetString(GL_EXTENSIONS)))
			extensions = [[NSString alloc] initWithCString:(const char *)glStr];
		    
		    [NSOpenGLContext clearCurrentContext];
		}
                [context release];
	    }
            [pixelFormat release];
	}
	CFDictionarySetValue(info, CFSTR("gl_vendor0"), (CFStringRef)vendor);
	CFDictionarySetValue(info, CFSTR("gl_version0"), (CFStringRef)version);
	CFDictionarySetValue(info, CFSTR("gl_renderer0"), (CFStringRef)renderer);
	CFDictionarySetValue(info, CFSTR("gl_extensions0"), (CFStringRef)extensions);
    } while (0);
    
    // Network speed (as selected in the user's QuickTime preferences, instead of trying to figure it out ourselves)
    {
        EnterMovies();
        
        QTAtomContainer             prefs;
        QTAtom                      prefsAtom;
        ConnectionSpeedPrefsRecord  prefrec;
        OSErr err = GetQuickTimePreference(ConnectionSpeedPrefsType, &prefs);
        if (err == noErr) {
            prefsAtom = QTFindChildByID(prefs, kParentAtomIsContainer, ConnectionSpeedPrefsType, 1, nil);
            if (prefsAtom) {
                long  dataSize;
                Ptr   atomData;
                err = QTGetAtomDataPtr(prefs, prefsAtom, &dataSize, &atomData);
                if (err == noErr && dataSize == sizeof(ConnectionSpeedPrefsRecord)) {
                    // everything was fine -- read the connection speed (which is stored in big-endian format)
                    prefrec = *(ConnectionSpeedPrefsRecord *)atomData;
		    prefrec.connectionSpeed = CFSwapInt32BigToHost(prefrec.connectionSpeed);
		    
                    CFStringRef value = CFStringCreateWithFormat(kCFAllocatorDefault, NULL, CFSTR("%d"), prefrec.connectionSpeed);
                    CFDictionarySetValue(info, CFSTR("qt_netspeed"), value);
                    CFRelease(value);
                }
            }
            QTDisposeAtomContainer(prefs);
        }
        
        ExitMovies();
    }
    
    // More info on the general hardware from system_profiler
    {
	NSDictionary *profile = copySystemProfileForDataType(@"SPHardwareDataType");
	NSString *value;
	
	if ((value = [profile objectForKey:@"cpu_type"]))
	    CFDictionarySetValue(info, CFSTR("cpu_type"), (CFStringRef)value);
        
	if ((value = [profile objectForKey:@"machine_name"]))
	    CFDictionarySetValue(info, CFSTR("machine_name"), (CFStringRef)value);
        
	[profile release];
    }
    
    // More info on the display from system_profiler
    // TODO: Not handling multiple displays here, but really we just want to get the mapping from the displays to names straight.
    {
	NSDictionary *profile = copySystemProfileForDataType(@"SPDisplaysDataType");
	NSString *value;
	
	if ((value = [profile objectForKey:@"_name"]))
	    CFDictionarySetValue(info, CFSTR("adaptor0_name"), (CFStringRef)value);
	
	[profile release];
    }
    
    // Number of audio output channels on the default output device (i.e., are they supporting 5.1 audio)
    
    return info;
}

